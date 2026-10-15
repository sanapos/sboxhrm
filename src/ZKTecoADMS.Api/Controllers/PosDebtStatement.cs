using ZKTecoADMS.Api.Controllers.Base;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>Sổ đối chiếu công nợ (khách hàng / nhà cung cấp) từ sổ công nợ: đầu kỳ, phát sinh tăng / giảm, cuối kỳ.</summary>
internal static class PosDebtStatement
{
    static string Label(string docType) => docType switch
    {
        "Opening" => "Số dư đầu (trước khi có sổ)",
        "Sale" => "Bán hàng",
        "SaleCancel" => "Hủy đơn bán",
        "Return" => "Khách trả hàng",
        "ReturnVoid" => "Hủy phiếu trả hàng",
        "Payment" => "Thanh toán",
        "Receipt" => "Nhập hàng",
        "ReceiptCancel" => "Hủy phiếu nhập",
        "PurchaseReturn" => "Trả hàng NCC",
        "PurchaseReturnCancel" => "Hủy phiếu trả NCC",
        _ => docType,
    };

    /// <param name="from">Ngày VN (mặc định đầu tháng).</param>
    /// <param name="to">Ngày VN (mặc định hôm nay).</param>
    public static async Task<object> BuildAsync(
        ZKTecoDbContext db, Guid storeId, string partyType, Guid partyId, decimal currentBalance,
        DateTime? from, DateTime? to, ZKTecoADMS.Application.Interfaces.IBranchContext? branchCtx = null)
    {
        var todayVn = VnTimeHelper.NowVn().Date;
        var fromVn = (from ?? new DateTime(todayVn.Year, todayVn.Month, 1)).Date;
        var toVn = (to ?? todayVn).Date;
        if (toVn < fromVn) (fromVn, toVn) = (toVn, fromVn);
        var fromUtc = fromVn.AddHours(-7);
        var toUtc = toVn.AddDays(1).AddHours(-7);

        var q = db.PosDebtLedgerEntries.AsNoTracking()
            .Where(e => e.StoreId == storeId && e.PartyType == partyType && e.PartyId == partyId);
        // Xem theo chi nhánh: số dư là phát sinh của riêng chi nhánh (cộng dồn Delta), không phải số dư cả cửa hàng.
        var branchScoped = branchCtx is { StoreUsesBranches: true } && (branchCtx.FilterBranchId != null || branchCtx.AllowedBranchIds != null);
        if (branchScoped) q = q.ApplyBranchScope(branchCtx);
        decimal opening;
        if (branchScoped)
            opening = await q.Where(e => e.At < fromUtc).SumAsync(e => (decimal?)e.Delta) ?? 0;
        else
        {
            var last = await q.Where(e => e.At < fromUtc)
                .OrderByDescending(e => e.At).ThenByDescending(e => e.CreatedAt)
                .Select(e => (decimal?)e.BalanceAfter).FirstOrDefaultAsync();
            opening = last ?? 0;
        }
        var rows = await q.Where(e => e.At >= fromUtc && e.At < toUtc)
            .OrderBy(e => e.At).ThenBy(e => e.CreatedAt)
            .ToListAsync();
        var running = opening;
        var balances = new Dictionary<Guid, decimal>();
        foreach (var r in rows)
            balances[r.Id] = branchScoped ? (running += r.Delta) : r.BalanceAfter;
        var increase = rows.Where(r => r.Delta > 0).Sum(r => r.Delta);
        var decrease = -rows.Where(r => r.Delta < 0).Sum(r => r.Delta);
        var closing = rows.Count > 0 ? balances[rows[^1].Id] : opening;

        return new
        {
            from = fromVn,
            to = toVn,
            opening,
            increase,
            decrease,
            closing,
            currentBalance,
            items = rows.Select(r => new
            {
                r.Id,
                at = VnTimeHelper.UtcToVn(r.At),
                r.DocType,
                docLabel = Label(r.DocType),
                r.DocId,
                r.DocNo,
                increase = r.Delta > 0 ? r.Delta : 0,
                decrease = r.Delta < 0 ? -r.Delta : 0,
                balance = balances[r.Id],
                r.Note,
            }).ToList(),
        };
    }
}

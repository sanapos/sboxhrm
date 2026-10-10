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
        DateTime? from, DateTime? to)
    {
        var todayVn = VnTimeHelper.NowVn().Date;
        var fromVn = (from ?? new DateTime(todayVn.Year, todayVn.Month, 1)).Date;
        var toVn = (to ?? todayVn).Date;
        if (toVn < fromVn) (fromVn, toVn) = (toVn, fromVn);
        var fromUtc = fromVn.AddHours(-7);
        var toUtc = toVn.AddDays(1).AddHours(-7);

        var q = db.PosDebtLedgerEntries.AsNoTracking()
            .Where(e => e.StoreId == storeId && e.PartyType == partyType && e.PartyId == partyId);
        var last = await q.Where(e => e.At < fromUtc)
            .OrderByDescending(e => e.At).ThenByDescending(e => e.CreatedAt)
            .Select(e => (decimal?)e.BalanceAfter).FirstOrDefaultAsync();
        var opening = last ?? 0;
        var rows = await q.Where(e => e.At >= fromUtc && e.At < toUtc)
            .OrderBy(e => e.At).ThenBy(e => e.CreatedAt)
            .ToListAsync();
        var increase = rows.Where(r => r.Delta > 0).Sum(r => r.Delta);
        var decrease = -rows.Where(r => r.Delta < 0).Sum(r => r.Delta);
        var closing = rows.Count > 0 ? rows[^1].BalanceAfter : opening;

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
                balance = r.BalanceAfter,
                r.Note,
            }).ToList(),
        };
    }
}

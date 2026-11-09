using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Services;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// Tiền két của một ca thu ngân = tiền đầu ca + mọi phiếu thu tiền mặt − mọi phiếu chi tiền mặt do CHÍNH người mở ca
/// ghi trong giờ ca (theo sổ quỹ, cùng nguồn với «Tổng kết cuối ngày»).
/// <para>Trước đây chỉ cộng đơn có phương thức đúng chữ «Tiền mặt» và khớp người bán theo email: đơn trả
/// «Tiền mặt + Chuyển khoản» mất cả phần tiền mặt, không trừ tiền hoàn / phiếu chi, không cộng tiền thu nợ / cọc,
/// đơn phục vụ tạo nhưng thu ngân thu tiền không vào ca → két đúng mà vẫn báo lệch.</para>
/// </summary>
public static class PosShiftCashHelper
{
    public sealed record Breakdown(
        decimal OpeningCash,
        decimal SaleCash,
        decimal DebtCash,
        decimal DepositCash,
        decimal OtherCashIn,
        decimal RefundCash,
        decimal DepositRefundCash,
        decimal OtherCashOut,
        decimal ExpectedCash,
        List<(string Method, decimal Total, int Count)> SalePayments,
        List<Guid> SaleOrderIds);

    public static string PayLabel(PaymentMethodType method) => method switch
    {
        PaymentMethodType.Cash => "Tiền mặt",
        PaymentMethodType.BankTransfer => "Chuyển khoản",
        PaymentMethodType.VietQR => "VietQR",
        PaymentMethodType.Card => "Thẻ",
        PaymentMethodType.EWallet => "Ví điện tử",
        _ => "Khác",
    };

    static Guid? OrderIdOf(string? note)
    {
        if (note == null || !note.StartsWith(PosFinanceSyncHelper.SaleMarker)) return null;
        var rest = note[PosFinanceSyncHelper.SaleMarker.Length..];
        var bar = rest.IndexOf('|');
        return Guid.TryParse(bar >= 0 ? rest[..bar] : rest, out var id) ? id : null;
    }

    public static async Task<Breakdown> ComputeAsync(ZKTecoDbContext db, PosCashierShift shift, Guid? headquarterBranchId)
    {
        var from = shift.OpenedAt;
        var to = shift.ClosedAt ?? DateTime.UtcNow;
        var hq = headquarterBranchId ?? Guid.Empty;
        var branch = shift.BranchId;
        // Đơn bán offline đồng bộ muộn: phiếu thu sinh lúc đồng bộ nhưng tiền vào két lúc bán → tính theo giờ bán
        // (OfflineAt) — trước đây rơi sang ca đang mở lúc có mạng lại (ca sau báo thừa, ca bán báo thiếu).
        // Đồng bộ muộn nhất 7 ngày (PosOfflineSaleRules).
        var lateUntil = to.AddDays(7);
        var rows = await db.CashTransactions.AsNoTracking()
            .Where(c => c.StoreId == shift.StoreId && c.Deleted == null && c.IsActive &&
                        c.Status == CashTransactionStatus.Completed &&
                        c.CreatedByUserId == shift.OpenedByUserId &&
                        (branch == null || (c.BranchId ?? hq) == branch) &&
                        ((c.CreatedAt >= from && c.CreatedAt <= to) ||
                         (c.CreatedAt > to && c.CreatedAt <= lateUntil && c.InternalNote != null &&
                          c.InternalNote.StartsWith(PosFinanceSyncHelper.SaleMarker))))
            .Select(c => new { c.Type, c.Amount, c.PaymentMethod, c.InternalNote, c.CreatedAt })
            .ToListAsync();
        var saleOrderIds = rows.Select(r => OrderIdOf(r.InternalNote)).Where(x => x.HasValue).Select(x => x!.Value)
            .Distinct().ToList();
        var offlineAt = saleOrderIds.Count == 0
            ? new Dictionary<Guid, DateTime>()
            : await db.PosSaleOrders.AsNoTracking()
                .Where(o => o.StoreId == shift.StoreId && saleOrderIds.Contains(o.Id) && o.OfflineAt != null)
                .ToDictionaryAsync(o => o.Id, o => o.OfflineAt!.Value);
        var tx = rows.Where(r =>
        {
            var at = OrderIdOf(r.InternalNote) is Guid oid && offlineAt.TryGetValue(oid, out var sold) ? sold : r.CreatedAt;
            return at >= from && at <= to;
        }).ToList();

        bool Has(string? note, string marker) => note != null && note.StartsWith(marker);
        var cashIn = tx.Where(t => t.Type == CashTransactionType.Income && t.PaymentMethod == PaymentMethodType.Cash).ToList();
        var cashOut = tx.Where(t => t.Type == CashTransactionType.Expense && t.PaymentMethod == PaymentMethodType.Cash).ToList();

        var sale = cashIn.Where(t => Has(t.InternalNote, PosFinanceSyncHelper.SaleMarker)).Sum(t => t.Amount);
        var debt = cashIn.Where(t => Has(t.InternalNote, PosFinanceSyncHelper.CustomerPaymentMarker)).Sum(t => t.Amount);
        var deposit = cashIn.Where(t => Has(t.InternalNote, PosFinanceSyncHelper.ReservationDepositMarker)).Sum(t => t.Amount);
        var otherIn = cashIn.Sum(t => t.Amount) - sale - debt - deposit;
        var refund = cashOut.Where(t => Has(t.InternalNote, PosFinanceSyncHelper.CustomerReturnMarker)).Sum(t => t.Amount);
        var depositRefund = cashOut.Where(t => Has(t.InternalNote, PosFinanceSyncHelper.ReservationDepositRefundMarker)).Sum(t => t.Amount);
        var otherOut = cashOut.Sum(t => t.Amount) - refund - depositRefund;

        var saleTx = tx.Where(t => t.Type == CashTransactionType.Income && Has(t.InternalNote, PosFinanceSyncHelper.SaleMarker)).ToList();
        var payments = saleTx
            .GroupBy(t => PayLabel(t.PaymentMethod))
            .Select(g => (g.Key, g.Sum(x => x.Amount), g.Count()))
            .OrderByDescending(x => x.Item2)
            .ToList();
        var orderIds = saleTx.Select(t => OrderIdOf(t.InternalNote)).Where(x => x.HasValue).Select(x => x!.Value).Distinct().ToList();

        var expected = shift.OpeningCash + cashIn.Sum(t => t.Amount) - cashOut.Sum(t => t.Amount);
        return new Breakdown(shift.OpeningCash, sale, debt, deposit, otherIn, refund, depositRefund, otherOut,
            expected, payments, orderIds);
    }
}

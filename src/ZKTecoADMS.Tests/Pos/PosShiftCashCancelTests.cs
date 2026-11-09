using Microsoft.EntityFrameworkCore;
using Xunit;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure.Services;

namespace ZKTecoADMS.Tests.Pos;

/// <summary>Tiền ca / sổ quỹ khi hủy đơn của ngày / ca đã khép và khi đơn offline đồng bộ muộn.</summary>
[Collection("pos-pg")]
public class PosShiftCashCancelTests(PosPgFixture fx) : PosFlowTestBase(fx)
{
    async Task<Guid> UserOfAsync(Guid store)
    {
        await using var db = Fx.NewDb();
        return await db.Users.Where(u => u.StoreId == store).Select(u => u.Id).FirstAsync();
    }

    async Task<List<CashTransaction>> OrderCashAsync(Guid store, Guid orderId)
    {
        await using var db = Fx.NewDb();
        var sale = $"{PosFinanceSyncHelper.SaleMarker}{orderId}";
        var refund = $"{PosFinanceSyncHelper.CustomerReturnMarker}{orderId}";
        return await db.CashTransactions
            .Where(c => c.StoreId == store && c.Deleted == null && c.InternalNote != null
                && (c.InternalNote.StartsWith(sale) || c.InternalNote.StartsWith(refund)))
            .ToListAsync();
    }

    async Task<Guid> AddShiftAsync(Guid store, Guid user, DateTime openedAt, DateTime? closedAt)
    {
        var s = new PosCashierShift
        {
            Id = Guid.NewGuid(), StoreId = store, OpenedAt = openedAt, OpenedByUserId = user, OpeningCash = 0,
            ClosedAt = closedAt, Status = closedAt == null ? "Open" : "Closed",
        };
        await using var db = Fx.NewDb();
        db.PosCashierShifts.Add(s);
        await db.SaveChangesAsync();
        return s.Id;
    }

    async Task<PosShiftCashHelper.Breakdown> ShiftAsync(Guid shiftId)
    {
        await using var db = Fx.NewDb();
        var s = await db.PosCashierShifts.FirstAsync(x => x.Id == shiftId);
        return await PosShiftCashHelper.ComputeAsync(db, s, null);
    }

    async Task CancelAsync(Guid store, Guid orderId)
    {
        await using var db = Fx.NewDb();
        Assert.Null(Error(await Sales(db, store).CancelSale(orderId)));
    }

    [Fact]
    public async Task Cancelling_yesterdays_cash_sale_keeps_its_receipt_and_refunds_from_todays_shift()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var user = await UserOfAsync(store);
        var p = (await Fx.AddProductAsync(store, "Trà", PosProductType.Goods, 50, 4000, 10000)).Id;
        var order = await SellAsync(store, (p, 2, 10000, null));
        await using (var db = Fx.NewDb())
            await db.CashTransactions.Where(c => c.StoreId == store).ExecuteUpdateAsync(s => s
                .SetProperty(c => c.TransactionDate, c => c.TransactionDate.AddDays(-1))
                .SetProperty(c => c.CreatedAt, c => c.CreatedAt.AddDays(-1)));
        var shift = await AddShiftAsync(store, user, DateTime.UtcNow.AddMinutes(-5), null);

        await CancelAsync(store, order.Id);

        var cash = await OrderCashAsync(store, order.Id);
        var receipt = Assert.Single(cash, c => c.Type == CashTransactionType.Income);
        Assert.True(receipt.IsActive);
        Assert.Equal(CashTransactionStatus.Completed, receipt.Status);
        var refund = Assert.Single(cash, c => c.Type == CashTransactionType.Expense);
        Assert.Equal(20000m, refund.Amount);
        Assert.Equal(PaymentMethodType.Cash, refund.PaymentMethod);
        Assert.Equal(user, refund.CreatedByUserId);
        Assert.Contains($"|{PosFinanceSyncHelper.CancelRefundTag}|", refund.InternalNote);

        var b = await ShiftAsync(shift);
        Assert.Equal(20000m, b.RefundCash);
        Assert.Equal(-20000m, b.ExpectedCash);
    }

    [Fact]
    public async Task Cancelling_a_sale_from_a_closed_shift_today_also_refunds_instead_of_rewriting_it()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var user = await UserOfAsync(store);
        var p = (await Fx.AddProductAsync(store, "Bánh", PosProductType.Goods, 50, 4000, 10000)).Id;
        var closed = await AddShiftAsync(store, user, DateTime.UtcNow.AddHours(-2), null);
        var order = await SellAsync(store, (p, 1, 10000, null));
        await using (var db = Fx.NewDb())
            await db.PosCashierShifts.Where(s => s.Id == closed).ExecuteUpdateAsync(s => s
                .SetProperty(x => x.ClosedAt, DateTime.UtcNow).SetProperty(x => x.Status, "Closed"));

        await CancelAsync(store, order.Id);

        var cash = await OrderCashAsync(store, order.Id);
        Assert.True(Assert.Single(cash, c => c.Type == CashTransactionType.Income).IsActive);
        Assert.Equal(10000m, Assert.Single(cash, c => c.Type == CashTransactionType.Expense).Amount);
        // Ca đã đóng vẫn giữ tiền đã thu.
        Assert.Equal(10000m, (await ShiftAsync(closed)).SaleCash);
    }

    [Fact]
    public async Task Cancelling_a_sale_of_the_same_open_day_cancels_its_receipt()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var p = (await Fx.AddProductAsync(store, "Cơm", PosProductType.Goods, 50, 4000, 10000)).Id;
        var order = await SellAsync(store, (p, 1, 10000, null));

        await CancelAsync(store, order.Id);

        var cash = Assert.Single(await OrderCashAsync(store, order.Id));
        Assert.Equal(CashTransactionType.Income, cash.Type);
        Assert.False(cash.IsActive && cash.Status == CashTransactionStatus.Completed);
    }

    [Fact]
    public async Task Offline_sale_synced_later_counts_in_the_shift_it_was_sold_in()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var user = await UserOfAsync(store);
        var p = (await Fx.AddProductAsync(store, "Phở", PosProductType.Goods, 50, 4000, 10000)).Id;
        var now = DateTime.UtcNow;
        var shiftA = await AddShiftAsync(store, user, now.AddHours(-3), now.AddHours(-1));
        var shiftB = await AddShiftAsync(store, user, now.AddMinutes(-30), null);
        // Bán lúc mất mạng trong ca A, có mạng lại (phiếu thu sinh) trong ca B.
        var order = await SellAsync(store, (p, 3, 10000, null));
        await using (var db = Fx.NewDb())
            await db.PosSaleOrders.Where(o => o.Id == order.Id).ExecuteUpdateAsync(s => s
                .SetProperty(o => o.OfflineNo, "OFF-0001")
                .SetProperty(o => o.OfflineAt, now.AddHours(-2)));

        Assert.Equal(30000m, (await ShiftAsync(shiftA)).SaleCash);
        Assert.Equal(0m, (await ShiftAsync(shiftB)).SaleCash);
    }
}

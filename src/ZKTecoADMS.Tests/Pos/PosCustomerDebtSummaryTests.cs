using Microsoft.EntityFrameworkCore;
using Xunit;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Tests.Pos;

/// <summary>Nhắc nợ ở màn bán: tóm tắt nợ khách đọc mới (số nợ, số đơn còn nợ, đơn lâu nhất, lần thu gần nhất).</summary>
[Collection("pos-pg")]
public class PosCustomerDebtSummaryTests(PosPgFixture fx) : PosFlowTestBase(fx)
{
    [Fact]
    public async Task Ban_no_roi_thu_mot_phan_tom_tat_dung()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var p = await Fx.AddProductAsync(store, "Gạo", PosProductType.Goods, 100, 0, 100000);
        Guid customerId;
        await using (var db = Fx.NewDb())
        {
            var c = new PosCustomer { Id = Guid.NewGuid(), StoreId = store, CustomerCode = "KHNO1", Name = "Chị Ba", IsActive = true };
            db.PosCustomers.Add(c);
            await db.SaveChangesAsync();
            customerId = c.Id;
        }
        // Hai đơn bán nợ: 300.000 trả 100.000 (nợ 200.000), 100.000 trả 0.
        foreach (var (qty, paid) in new[] { (3m, 100000m), (1m, 0m) })
        {
            await using var db = Fx.NewDb();
            var dto = new PosSalesController.CreateSaleDto(
                [new PosSalesController.SaleLineDto(p.Id, qty, null, 100000, null)], 0, paid, "Tiền mặt", null, customerId, null);
            Data(await Sales(db, store).CreateSale(dto));
        }
        // Đơn đầu là đơn cũ 40 ngày.
        await using (var db = Fx.NewDb())
        {
            var first = await db.PosSaleOrders.AsTracking().Where(o => o.CustomerId == customerId).OrderBy(o => o.CreatedAt).FirstAsync();
            first.SaleDate = DateTime.UtcNow.AddDays(-40);
            await db.SaveChangesAsync();
        }
        await using (var db = Fx.NewDb())
        {
            var ctl = PosPgFixture.As(new PosCustomersController(db), store);
            var d = Data(await ctl.DebtSummary(customerId));
            object V(string k) => d.GetType().GetProperty(k)!.GetValue(d)!;
            Assert.Equal(300000m, (decimal)V("currentDebt"));
            Assert.Equal(2, (int)V("openOrderCount"));
            Assert.Equal(40, (int)V("oldestDays"));
            Assert.Equal(200000m, (decimal)V("over30"));
        }
        // Thu 250.000 (FIFO: hết đơn cũ 200.000, đơn mới còn 50.000).
        await using (var db = Fx.NewDb())
        {
            var ctl = PosPgFixture.As(new PosCustomersController(db), store);
            Data(await ctl.AddPayment(customerId, new(250000, "Tiền mặt", null, null)));
        }
        await using (var db = Fx.NewDb())
        {
            var ctl = PosPgFixture.As(new PosCustomersController(db), store);
            var d = Data(await ctl.DebtSummary(customerId));
            object? V(string k) => d.GetType().GetProperty(k)!.GetValue(d);
            Assert.Equal(50000m, (decimal)V("currentDebt")!);
            Assert.Equal(1, (int)V("openOrderCount")!);
            Assert.Equal(0, (int)V("oldestDays")!);
            Assert.Equal(250000m, (decimal)V("lastPaymentAmount")!);
        }
    }
}

using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using Xunit;

namespace ZKTecoADMS.Tests.Pos;

/// <summary>
/// Dòng dịch vụ tính giờ trên bàn: cửa hàng tắt «Tính tiền theo giờ» và dòng chưa bấm «Bắt đầu» → giữ SL nhập tay
/// (màn bán cũng không đếm giờ). Trước đây server lấy giờ mở bàn → chốt đơn tổng tăng mà tiền khách trả giữ nguyên.
/// </summary>
[Collection("pos-pg")]
public class PosTimedLineHourlyOffTests(PosPgFixture fx) : PosFlowTestBase(fx)
{
    async Task<(Guid store, Guid timed, Guid table)> SeedAsync(bool hourlyBilling)
    {
        var store = await Fx.NewStoreAsync();
        var timed = (await Fx.AddProductAsync(store, "Giờ phòng", PosProductType.Service, 0, 0, 120000,
            p => p.ServiceBillingMode = PosServiceBillingMode.PerHour)).Id;
        var area = Guid.NewGuid();
        var table = Guid.NewGuid();
        await using var db = Fx.NewDb();
        db.PosServiceAreas.Add(new PosServiceArea { Id = area, StoreId = store, Name = "Khu" });
        db.PosServiceResources.Add(new PosServiceResource { Id = table, StoreId = store, AreaId = area, Code = "P2", Name = "Phòng 2" });
        db.PosStoreSellSettings.Add(new PosStoreSellSettings
        {
            Id = Guid.NewGuid(), StoreId = store, EnableResources = true, EnableHourlyBilling = hourlyBilling,
        });
        await db.SaveChangesAsync();
        return (store, timed, table);
    }

    async Task<Guid> OpenTableDraftAsync(Guid store, Guid timed, Guid table, decimal qty)
    {
        await using (var db = Fx.NewDb())
            Data(await Sales(db, store).CreateSale(new PosSalesController.CreateSaleDto(
                [new PosSalesController.SaleLineDto(timed, qty, null, 120000, null)], 0, 0, "Tiền mặt", null, null, null,
                Complete: false, ServiceResourceId: table, ClientRequestId: "cr-" + Guid.NewGuid().ToString("N")[..8])));
        await using (var db = Fx.NewDb())
        {
            var order = await db.PosSaleOrders.SingleAsync(o => o.StoreId == store && o.ServiceResourceId == table);
            // Bàn mở từ 144 phút trước (như HD…0002: mở 20:40, chốt 23:03).
            var opened = DateTime.UtcNow.AddMinutes(-144);
            await db.PosSaleOrders.Where(o => o.Id == order.Id)
                .ExecuteUpdateAsync(s => s.SetProperty(o => o.ServiceStartedAt, opened));
            // Dòng đã được gắn mốc (bật tính theo giờ) → mốc = giờ mở bàn.
            await db.PosSaleOrderLines.Where(l => l.SaleOrderId == order.Id && l.ServiceStartedAt != null)
                .ExecuteUpdateAsync(s => s.SetProperty(l => l.ServiceStartedAt, opened));
            return order.Id;
        }
    }

    [Fact]
    public async Task HourlyOff_ManualQty_KeptOnSaveAndComplete()
    {
        if (NoDb) return;
        var (store, timed, table) = await SeedAsync(hourlyBilling: false);
        var orderId = await OpenTableDraftAsync(store, timed, table, 0.5m);
        await using (var db = Fx.NewDb())
        {
            var line = await db.PosSaleOrderLines.SingleAsync(l => l.SaleOrderId == orderId);
            Assert.Equal(0.5m, line.Qty);
            Assert.Equal(60000m, line.LineTotal);
            Assert.Null(line.ServiceStartedAt);
        }
        await using (var db = Fx.NewDb())
            Data(await Sales(db, store).CompleteSale(orderId, new PosSalesController.CompleteSaleDto()));
        var done = await OrderAsync(orderId);
        Assert.Equal(PosSaleOrderStatus.Completed, done.Status);
        Assert.Equal(60000m, done.Total);
        await using (var db = Fx.NewDb())
            Assert.Equal(0.5m, (await db.PosSaleOrderLines.SingleAsync(l => l.SaleOrderId == orderId)).Qty);
    }

    [Fact]
    public async Task HourlyOn_BillsFromTableOpen_OnComplete()
    {
        if (NoDb) return;
        var (store, timed, table) = await SeedAsync(hourlyBilling: true);
        var orderId = await OpenTableDraftAsync(store, timed, table, 0.5m);
        await using (var db = Fx.NewDb())
            Data(await Sales(db, store).CompleteSale(orderId, new PosSalesController.CompleteSaleDto()));
        await using (var db = Fx.NewDb())
        {
            var line = await db.PosSaleOrderLines.SingleAsync(l => l.SaleOrderId == orderId);
            // Bật tính theo giờ: vẫn tính từ giờ mở bàn (~144 phút ≈ 2,4 giờ) như trước.
            Assert.InRange(line.Qty, 2.3m, 2.5m);
            Assert.True(line.BillableMinutes >= 143);
        }
    }

    [Fact]
    public void TimedLineStart_FollowsSellScreenRule()
    {
        var line = DateTime.UtcNow.AddMinutes(-30);
        var open = DateTime.UtcNow.AddMinutes(-144);
        var off = new PosStoreSellSettings { EnableHourlyBilling = false };
        var on = new PosStoreSellSettings { EnableHourlyBilling = true };
        Assert.Equal(line, PosSalesController.TimedLineStart(line, open, off));
        Assert.Null(PosSalesController.TimedLineStart(null, open, off));
        Assert.Null(PosSalesController.TimedLineStart(null, open, null));
        Assert.Equal(open, PosSalesController.TimedLineStart(null, open, on));
    }
}

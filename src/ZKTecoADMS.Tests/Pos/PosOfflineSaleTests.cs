using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Tests.Pos;

/// <summary>Bán offline: đồng bộ không tạo đơn đôi, giờ bán thật, cấp dải số, kiểm soát cài lại app / nhảy số.</summary>
[Collection("pos-pg")]
public class PosOfflineSaleTests(PosPgFixture fx) : PosFlowTestBase(fx)
{
    PosOfflineController Offline(ZKTecoADMS.Infrastructure.ZKTecoDbContext db, Guid store) =>
        PosPgFixture.As(new PosOfflineController(db, NullLogger<PosOfflineController>.Instance), store);

    PosSalesController.CreateSaleDto OfflineDto(Guid product, string offlineNo, DateTime at, decimal qty = 1) =>
        new([new PosSalesController.SaleLineDto(product, qty, null, 10000, null)],
            0, 10000 * qty, "Tiền mặt", null, null, null,
            ClientRequestId: "cr-" + offlineNo, OfflineNo: offlineNo, OfflineAt: at, OfflineDeviceKey: "a:dev-1");

    async Task EnableOfflineAsync(Guid store)
    {
        await using var db = Fx.NewDb();
        var s = await db.PosStoreSellSettings.FirstOrDefaultAsync(x => x.StoreId == store);
        if (s == null)
        {
            s = new PosStoreSellSettings { Id = Guid.NewGuid(), StoreId = store, IsActive = true };
            db.PosStoreSellSettings.Add(s);
        }
        s.ExtraJson = "{\"offlineSale\":{\"enabled\":true,\"maxHours\":8}}";
        await db.SaveChangesAsync();
    }

    [Fact]
    public void Rules_parse_and_validate()
    {
        Assert.Equal("OFF-000123", PosOfflineSaleRules.NormalizeNo(" off-000123 "));
        Assert.Null(PosOfflineSaleRules.NormalizeNo("HD123"));
        Assert.Equal(123, PosOfflineSaleRules.SeqOf("OFF-000123"));
        Assert.False(PosOfflineSaleRules.ParseSettings(null).Enabled);
        Assert.False(PosOfflineSaleRules.ParseSettings("{\"offlineSale\":{\"enabled\":false}}").Enabled);
        var on = PosOfflineSaleRules.ParseSettings("{\"offlineSale\":{\"enabled\":true,\"maxHours\":500}}");
        Assert.True(on.Enabled);
        Assert.Equal(72, on.MaxHours);
        var now = DateTime.UtcNow;
        Assert.Null(PosOfflineSaleRules.ResolveOfflineSaleAt("OFF-1", now.AddDays(-10), now, true));
        Assert.Null(PosOfflineSaleRules.ResolveOfflineSaleAt("OFF-1", now.AddHours(1), now, true));
        Assert.Null(PosOfflineSaleRules.ResolveOfflineSaleAt("OFF-1", now.AddHours(-1), now, false));
        Assert.Equal(now.AddHours(-2), PosOfflineSaleRules.ResolveOfflineSaleAt("OFF-1", now.AddHours(-2), now, true));
    }

    [Fact]
    public async Task Offline_sale_sync_is_idempotent_backdated_and_allows_negative_stock()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var p = (await Fx.AddProductAsync(store, "Bánh", PosProductType.Goods, 1, 4000, 10000)).Id;
        var at = DateTime.UtcNow.AddHours(-3);

        PosSalesController.SaleOrderDto first;
        await using (var db = Fx.NewDb())
            first = Data(await Sales(db, store).CreateSale(OfflineDto(p, "OFF-000007", at, qty: 3)));
        // Gửi lại (mất mạng lúc nhận kết quả) — cùng số offline, mã yêu cầu khác.
        PosSalesController.SaleOrderDto again;
        await using (var db = Fx.NewDb())
        {
            var dto = OfflineDto(p, "OFF-000007", at, qty: 3) with { ClientRequestId = "cr-other" };
            again = Data(await Sales(db, store).CreateSale(dto));
        }
        Assert.Equal(first.Id, again.Id);

        var order = await OrderAsync(first.Id);
        Assert.Equal("OFF-000007", order.OfflineNo);
        Assert.Equal("a:dev-1", order.OfflineDeviceKey);
        Assert.True(Math.Abs(((order.SaleDate ?? order.CreatedAt) - at).TotalSeconds) < 2);
        // Tồn 1, bán 3 lúc mất mạng → đồng bộ vẫn nhận (âm kho), không mất đơn đã thu tiền.
        Assert.Equal(-2, await OnHandAsync(p));
        await using (var db = Fx.NewDb())
            Assert.Equal(1, await db.PosSaleOrders.CountAsync(o => o.StoreId == store && o.OfflineNo == "OFF-000007"));
    }

    [Fact]
    public async Task Invalid_offline_no_is_ignored()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var p = (await Fx.AddProductAsync(store, "Nước", PosProductType.Goods, 10, 4000, 10000)).Id;
        await using var db = Fx.NewDb();
        var r = Data(await Sales(db, store).CreateSale(OfflineDto(p, "HD-1", DateTime.UtcNow.AddHours(-5))));
        var order = await OrderAsync(r.Id);
        Assert.Null(order.OfflineNo);
        // Không phải offline → giờ bán = giờ server, không lùi theo giờ máy.
        Assert.True((DateTime.UtcNow - (order.SaleDate ?? order.CreatedAt)).TotalMinutes < 5);
    }

    [Fact]
    public async Task Reserve_requires_enabled_and_gives_consecutive_blocks()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var dto = new PosOfflineController.ReserveDto { DeviceKey = "a:dev-1", InstallId = "inst-1", Count = 20 };
        await InstallAsync(store, "a:dev-1", "inst-1");
        await InstallAsync(store, "a:dev-2", "i2");
        await using (var db = Fx.NewDb())
            Assert.NotNull(Error(await Offline(db, store).Reserve(dto, default)));
        await EnableOfflineAsync(store);
        await using (var db = Fx.NewDb())
            await Offline(db, store).Reserve(dto, default);
        await using (var db = Fx.NewDb())
            await Offline(db, store).Reserve(new PosOfflineController.ReserveDto { DeviceKey = "a:dev-2", InstallId = "i2", Count = 10 }, default);
        await using (var db = Fx.NewDb())
        {
            var blocks = await db.PosOfflineSerialBlocks.Where(b => b.StoreId == store).OrderBy(b => b.FromSeq).ToListAsync();
            Assert.Equal(2, blocks.Count);
            Assert.Equal((1, 20), (blocks[0].FromSeq, blocks[0].ToSeq));
            Assert.Equal((21, 30), (blocks[1].FromSeq, blocks[1].ToSeq));
        }
    }

    async Task InstallAsync(Guid store, string deviceKey, string installId, string platform = "android")
    {
        await using var db = Fx.NewDb();
        await Offline(db, store).Install(new PosOfflineController.InstallDto
        {
            DeviceKey = deviceKey, InstallId = installId, DeviceName = "Máy", Platform = platform,
        }, default);
    }

    [Fact]
    public async Task Offline_table_sale_does_not_close_session_opened_on_server_by_other_device()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        await EnableOfflineAsync(store);
        var p = (await Fx.AddProductAsync(store, "Cà phê", PosProductType.Goods, 100, 4000, 10000)).Id;
        var area = Guid.NewGuid();
        var table = Guid.NewGuid();
        var session = Guid.NewGuid();
        await using (var db = Fx.NewDb())
        {
            db.PosServiceAreas.Add(new PosServiceArea { Id = area, StoreId = store, Name = "Tầng 1" });
            db.PosServiceResources.Add(new PosServiceResource { Id = table, StoreId = store, AreaId = area, Code = "B9", Name = "Bàn 9" });
            // Máy khác mở bàn trên máy chủ trong lúc máy này mất mạng.
            db.PosResourceSessions.Add(new PosResourceSession
            {
                Id = session, StoreId = store, ResourceId = table, StartedAt = DateTime.UtcNow.AddMinutes(-5),
                Status = PosResourceSessionStatus.Open,
            });
            await db.SaveChangesAsync();
        }
        await using (var db = Fx.NewDb())
            Data(await Sales(db, store).CreateSale(
                OfflineDto(p, "OFF-000007", DateTime.UtcNow.AddMinutes(-20)) with { ServiceResourceId = table }));
        await using (var db = Fx.NewDb())
        {
            var s = await db.PosResourceSessions.SingleAsync(x => x.Id == session);
            Assert.Equal(PosResourceSessionStatus.Open, s.Status);
            var order = await db.PosSaleOrders.SingleAsync(o => o.StoreId == store && o.OfflineNo == "OFF-000007");
            Assert.Equal(table, order.ServiceResourceId);
        }
    }

    [Fact]
    public async Task Paying_second_bill_on_table_keeps_session_of_other_open_bill()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var p = (await Fx.AddProductAsync(store, "Nem", PosProductType.Goods, 100, 4000, 10000)).Id;
        var area = Guid.NewGuid();
        var table = Guid.NewGuid();
        await using (var db = Fx.NewDb())
        {
            db.PosServiceAreas.Add(new PosServiceArea { Id = area, StoreId = store, Name = "Tầng 1" });
            db.PosServiceResources.Add(new PosServiceResource { Id = table, StoreId = store, AreaId = area, Code = "B8", Name = "Bàn 8" });
            await db.SaveChangesAsync();
        }
        // Hóa đơn của máy khác đang mở trên bàn (phiên gắn đơn nháp còn món).
        await using (var db = Fx.NewDb())
            Data(await Sales(db, store).CreateSale(new PosSalesController.CreateSaleDto(
                [new PosSalesController.SaleLineDto(p, 1, null, 10000, null)], 0, 0, "Tiền mặt", null, null, null,
                Complete: false, ServiceResourceId: table, ClientRequestId: "cr-main")));
        var session = Guid.NewGuid();
        await using (var db = Fx.NewDb())
        {
            var main = await db.PosSaleOrders.SingleAsync(o => o.StoreId == store && o.ServiceResourceId == table);
            db.PosResourceSessions.Add(new PosResourceSession
            {
                Id = session, StoreId = store, ResourceId = table, SaleOrderId = main.Id,
                StartedAt = DateTime.UtcNow.AddMinutes(-10), Status = PosResourceSessionStatus.Open,
            });
            await db.SaveChangesAsync();
        }
        // Hóa đơn thứ 2 trên cùng bàn (không gắn phiên) thanh toán → phiên của hóa đơn kia vẫn mở.
        await using (var db = Fx.NewDb())
            Data(await Sales(db, store).CreateSale(new PosSalesController.CreateSaleDto(
                [new PosSalesController.SaleLineDto(p, 1, null, 10000, null)], 0, 10000, "Tiền mặt", null, null, null,
                ServiceResourceId: table, ClientRequestId: "cr-second")));
        await using (var db = Fx.NewDb())
            Assert.Equal(PosResourceSessionStatus.Open,
                (await db.PosResourceSessions.SingleAsync(x => x.Id == session)).Status);

        // Giỏ mở offline trùng bàn → hóa đơn tách của hóa đơn đang mở; thanh toán nó không trả bàn / không xóa bill kia.
        await using (var db = Fx.NewDb())
            Data(await Sales(db, store).CreateSale(new PosSalesController.CreateSaleDto(
                [new PosSalesController.SaleLineDto(p, 2, null, 10000, null)], 0, 0, "Tiền mặt", null, null, null,
                Complete: false, ServiceResourceId: table, ClientRequestId: "cr-offline-conflict", SplitOfTableBill: true)));
        Guid mainId, splitId;
        await using (var db = Fx.NewDb())
        {
            mainId = (await db.PosResourceSessions.SingleAsync(x => x.Id == session)).SaleOrderId!.Value;
            var split = await db.PosSaleOrders.SingleAsync(o => o.StoreId == store && o.ClientRequestId == "cr-offline-conflict");
            Assert.Equal(mainId, split.SplitFromOrderId);
            Assert.Null(split.ResourceSessionId);
            splitId = split.Id;
        }
        await using (var db = Fx.NewDb())
            Data(await Sales(db, store).CompleteSale(splitId, new PosSalesController.CompleteSaleDto()));
        await using (var db = Fx.NewDb())
        {
            Assert.Equal(PosResourceSessionStatus.Open,
                (await db.PosResourceSessions.SingleAsync(x => x.Id == session)).Status);
            var main = await db.PosSaleOrders.SingleAsync(o => o.Id == mainId);
            Assert.Null(main.Deleted);
            Assert.Equal(PosSaleOrderStatus.Draft, main.Status);
            Assert.Equal(PosSaleOrderStatus.Completed,
                (await db.PosSaleOrders.SingleAsync(o => o.Id == splitId)).Status);
        }
    }

    [Fact]
    public async Task Reserve_rejects_web_and_unknown_installs()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        await EnableOfflineAsync(store);
        await InstallAsync(store, "d:web-1", "w1", platform: "web");
        await using (var db = Fx.NewDb())
            Assert.NotNull(Error(await Offline(db, store).Reserve(
                new PosOfflineController.ReserveDto { DeviceKey = "d:web-1", InstallId = "w1", Count = 10 }, default)));
        await using (var db = Fx.NewDb())
            Assert.NotNull(Error(await Offline(db, store).Reserve(
                new PosOfflineController.ReserveDto { DeviceKey = "a:never", InstallId = "x", Count = 10 }, default)));
        await using (var db = Fx.NewDb())
            Assert.False(await db.PosOfflineSerialBlocks.AnyAsync(b => b.StoreId == store));
    }

    [Fact]
    public async Task Audit_flags_gaps_and_reinstall_with_pending()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        await EnableOfflineAsync(store);
        var p = (await Fx.AddProductAsync(store, "Trà", PosProductType.Goods, 100, 4000, 10000)).Id;
        await using (var db = Fx.NewDb())
            await Offline(db, store).Install(new PosOfflineController.InstallDto
            {
                DeviceKey = "a:dev-1", InstallId = "inst-1", DeviceName = "Quầy 1", Platform = "android",
                PendingOfflineSales = 2, LastOfflineSeq = 4,
            }, default);
        await using (var db = Fx.NewDb())
            await Offline(db, store).Reserve(new PosOfflineController.ReserveDto { DeviceKey = "a:dev-1", InstallId = "inst-1", Count = 10 }, default);
        // Đồng bộ OFF-000001 và OFF-000003 → OFF-000002 nhảy cóc; máy báo đã bán tới 4 → OFF-000004 chưa về.
        foreach (var no in new[] { "OFF-000001", "OFF-000003" })
            await using (var db = Fx.NewDb())
                Data(await Sales(db, store).CreateSale(OfflineDto(p, no, DateTime.UtcNow.AddMinutes(-30))));
        // Cài lại app (xóa dữ liệu) — mã cài đặt mới trên cùng thiết bị.
        await using (var db = Fx.NewDb())
            await Offline(db, store).Install(new PosOfflineController.InstallDto
            {
                DeviceKey = "a:dev-1", InstallId = "inst-2", DeviceName = "Quầy 1", Platform = "android",
            }, default);

        PosOfflineAuditBuilder.Report audit;
        await using (var db = Fx.NewDb())
            audit = Data(await Offline(db, store).Audit(30, default));
        Assert.Equal("red", audit.Verdict);
        Assert.Contains("OFF-000002", audit.Blocks.Single().Gaps);             // nhảy cóc
        Assert.Contains("OFF-000004", audit.Blocks.Single().MissingReported);  // máy báo đã bán, chưa về
        Assert.Contains(audit.Alerts, a => a.Kind == "REINSTALL_PENDING");     // cài lại khi còn đơn chưa gửi
        Assert.Equal(1, audit.Summary.Reinstalls);
        Assert.Equal(2, audit.Summary.OfflineSales);
    }
}

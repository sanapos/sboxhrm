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
            ClientRequestId: "cr-" + offlineNo, OfflineNo: offlineNo, OfflineAt: at, OfflineDeviceKey: "dev-1");

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
        Assert.Equal("dev-1", order.OfflineDeviceKey);
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
        var dto = new PosOfflineController.ReserveDto { DeviceKey = "dev-1", InstallId = "inst-1", Count = 20 };
        await using (var db = Fx.NewDb())
            Assert.NotNull(Error(await Offline(db, store).Reserve(dto, default)));
        await EnableOfflineAsync(store);
        await using (var db = Fx.NewDb())
            await Offline(db, store).Reserve(dto, default);
        await using (var db = Fx.NewDb())
            await Offline(db, store).Reserve(new PosOfflineController.ReserveDto { DeviceKey = "dev-2", InstallId = "i2", Count = 10 }, default);
        await using (var db = Fx.NewDb())
        {
            var blocks = await db.PosOfflineSerialBlocks.Where(b => b.StoreId == store).OrderBy(b => b.FromSeq).ToListAsync();
            Assert.Equal(2, blocks.Count);
            Assert.Equal((1, 20), (blocks[0].FromSeq, blocks[0].ToSeq));
            Assert.Equal((21, 30), (blocks[1].FromSeq, blocks[1].ToSeq));
        }
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
                DeviceKey = "dev-1", InstallId = "inst-1", DeviceName = "Quầy 1",
                PendingOfflineSales = 2, LastOfflineSeq = 4,
            }, default);
        await using (var db = Fx.NewDb())
            await Offline(db, store).Reserve(new PosOfflineController.ReserveDto { DeviceKey = "dev-1", InstallId = "inst-1", Count = 10 }, default);
        // Đồng bộ OFF-000001 và OFF-000003 → OFF-000002 nhảy cóc; máy báo đã bán tới 4 → OFF-000004 chưa về.
        foreach (var no in new[] { "OFF-000001", "OFF-000003" })
            await using (var db = Fx.NewDb())
                Data(await Sales(db, store).CreateSale(OfflineDto(p, no, DateTime.UtcNow.AddMinutes(-30))));
        // Cài lại app (xóa dữ liệu) — mã cài đặt mới trên cùng thiết bị.
        await using (var db = Fx.NewDb())
            await Offline(db, store).Install(new PosOfflineController.InstallDto
            {
                DeviceKey = "dev-1", InstallId = "inst-2", DeviceName = "Quầy 1",
            }, default);

        object audit;
        await using (var db = Fx.NewDb())
            audit = Data(await Offline(db, store).Audit(30, default))!;
        var json = System.Text.Json.JsonSerializer.Serialize(audit, new System.Text.Json.JsonSerializerOptions
        {
            Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
        });
        Assert.Contains("OFF-000002", json);              // nhảy cóc
        Assert.Contains("OFF-000004", json);              // máy báo đã bán, chưa về
        Assert.Contains("Cài lại app", json);             // cài lại khi còn đơn chưa gửi
        Assert.Contains("\"reinstalls\":1", json);
    }
}

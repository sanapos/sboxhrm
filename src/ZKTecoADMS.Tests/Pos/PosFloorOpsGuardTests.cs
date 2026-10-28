using System.Text.Json;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Xunit;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Tests.Pos;

/// <summary>
/// Thao tác bàn (tách bill, chuyển / gộp bàn, trả bàn, số khách, báo bếp) không làm sau lưng máy đang mở bàn,
/// không đụng đơn đã thanh toán, chạy lần lượt khi 2 máy bấm cùng lúc.
/// </summary>
[Collection("pos-pg")]
public class PosFloorOpsGuardTests(PosPgFixture fx) : PosFlowTestBase(fx)
{
    const string Me = "dev-me";

    static PosSellIndustryController Floor(ZKTecoDbContext db, Guid store) =>
        PosPgFixture.As(new PosSellIndustryController(db, null!, null!, null!), store);

    record Shop(Guid Store, Guid Product, Guid Area);
    record Tbl(Guid Resource, Guid Session, Guid Order, Guid Line);

    async Task<Shop> ShopAsync()
    {
        var store = await Fx.NewStoreAsync();
        var product = (await Fx.AddProductAsync(store, "Lẩu", PosProductType.Goods, 100, 20000, 50000)).Id;
        var area = Guid.NewGuid();
        await using var db = Fx.NewDb();
        var s = await db.PosStoreSellSettings.AsTracking().FirstOrDefaultAsync(x => x.StoreId == store);
        if (s == null)
        {
            s = new PosStoreSellSettings { Id = Guid.NewGuid(), StoreId = store, IsActive = true };
            db.PosStoreSellSettings.Add(s);
        }
        s.SellProfile = PosSellProfile.Restaurant;
        db.PosServiceAreas.Add(new PosServiceArea { Id = area, StoreId = store, Name = "Tầng 1" });
        await db.SaveChangesAsync();
        return new Shop(store, product, area);
    }

    async Task<Guid> TableAsync(Shop shop, string name)
    {
        var id = Guid.NewGuid();
        await using var db = Fx.NewDb();
        db.PosServiceResources.Add(new PosServiceResource
        {
            Id = id, StoreId = shop.Store, AreaId = shop.Area, Code = name, Name = name, IsActive = true,
        });
        await db.SaveChangesAsync();
        return id;
    }

    /// <summary>Bàn đang có khách: phiên mở + đơn tạm 1 dòng. holder = máy khác đang giữ khóa (null = không ai).</summary>
    async Task<Tbl> OpenAsync(Shop shop, string name, decimal qty = 4, decimal sent = 4, decimal done = 2,
        (string Device, DateTime LockedAt)? holder = null)
    {
        var table = await TableAsync(shop, name);
        var session = Guid.NewGuid();
        var order = Guid.NewGuid();
        var line = Guid.NewGuid();
        var now = DateTime.UtcNow;
        await using var db = Fx.NewDb();
        db.PosResourceSessions.Add(new PosResourceSession
        {
            Id = session, StoreId = shop.Store, ResourceId = table, StartedAt = now.AddMinutes(-30),
            Status = PosResourceSessionStatus.Open, GuestCount = 2, IsActive = true,
        });
        db.PosSaleOrders.Add(new PosSaleOrder
        {
            Id = order, StoreId = shop.Store, OrderNo = "HD" + order.ToString("N")[..8], Status = PosSaleOrderStatus.Draft,
            SubTotal = qty * 50000, Total = qty * 50000, ServiceResourceId = table, ResourceSessionId = session,
            LockVersion = 3, IsActive = true,
            LockedByUserId = holder == null ? null : Guid.NewGuid(),
            LockedByDeviceId = holder?.Device,
            LockedByDeviceName = holder == null ? null : "Máy B",
            LockedByDisplayName = holder == null ? null : "b@q.vn",
            LockedAt = holder?.LockedAt,
            LockExpiresAt = holder == null ? null : now.AddMinutes(8),
            Lines = qty <= 0 ? [] : [new PosSaleOrderLine
            {
                Id = line, StoreId = shop.Store, ProductId = shop.Product, ProductName = "Lẩu", Qty = qty,
                UnitPrice = 50000, LineTotal = qty * 50000, KitchenSentQty = sent, KitchenDoneQty = done,
                KitchenSentAt = sent > 0 ? now : null, KitchenPrepStatus = sent > 0 ? "queued" : "none",
            }],
        });
        await db.SaveChangesAsync();
        await db.PosResourceSessions.Where(s => s.Id == session)
            .ExecuteUpdateAsync(x => x.SetProperty(s => s.SaleOrderId, order));
        return new Tbl(table, session, order, line);
    }

    static (string Device, DateTime LockedAt) OtherDeviceNow => ("dev-other", DateTime.UtcNow);

    async Task<int> OpenSessionsOnAsync(Guid resource)
    {
        await using var db = Fx.NewDb();
        return await db.PosResourceSessions.CountAsync(s => s.ResourceId == resource && s.Deleted == null
            && (s.Status == PosResourceSessionStatus.Open || s.Status == PosResourceSessionStatus.Paused));
    }

    static JsonElement Json(ActionResult<AppResponse<object>> r) =>
        JsonSerializer.SerializeToElement(((AppResponse<object>)((OkObjectResult)r.Result!).Value!).Data);

    [Fact]
    public async Task Split_bill_is_refused_while_another_device_has_the_table_open()
    {
        if (NoDb) return;
        var shop = await ShopAsync();
        var a = await OpenAsync(shop, "B1", holder: OtherDeviceNow);
        ActionResult<AppResponse<object>> r;
        await using (var db = Fx.NewDb())
            r = await Floor(db, shop.Store).SplitBill(a.Session, new PosSellIndustryController.SplitBillDto
            {
                Items = [new PosSellIndustryController.SplitBillItemDto { LineId = a.Line, Qty = 2 }],
                DeviceId = Me,
            });
        Assert.IsType<ConflictObjectResult>(r.Result);
        Assert.Contains("Bàn đang mở trên", Error(r));
        await using var check = Fx.NewDb();
        Assert.Equal(1, await check.PosSaleOrders.CountAsync(o => o.StoreId == shop.Store && o.Deleted == null));
        Assert.Equal(4, (await check.PosSaleOrderLines.SingleAsync(l => l.Id == a.Line)).Qty);
    }

    [Fact]
    public async Task Split_bill_after_holder_left_moves_kitchen_done_with_the_split_part()
    {
        if (NoDb) return;
        var shop = await ShopAsync();
        // Máy giữ bàn đã thoát / chết (quá 45 giây không gia hạn) → không chặn.
        var a = await OpenAsync(shop, "B1", holder: ("dev-other", DateTime.UtcNow.AddMinutes(-2)));
        Guid newOrder;
        await using (var db = Fx.NewDb())
        {
            var r = await Floor(db, shop.Store).SplitBill(a.Session, new PosSellIndustryController.SplitBillDto
            {
                Items = [new PosSellIndustryController.SplitBillItemDto { LineId = a.Line, Qty = 2 }],
                DeviceId = Me,
            });
            newOrder = Json(r).GetProperty("newSaleOrderId").GetGuid();
        }
        await using var check = Fx.NewDb();
        var remain = await check.PosSaleOrderLines.SingleAsync(l => l.Id == a.Line);
        var moved = await check.PosSaleOrderLines.SingleAsync(l => l.SaleOrderId == newOrder);
        Assert.Equal((2m, 2m), (remain.Qty, remain.KitchenSentQty));
        Assert.Equal((2m, 2m), (moved.Qty, moved.KitchenSentQty));
        // SL 4, bếp xong 2: phần xong đi theo bill tách, phần còn lại chưa xong (trước đây cả hai cùng «xong 2»).
        Assert.Equal(2m, moved.KitchenDoneQty);
        Assert.Equal(0m, remain.KitchenDoneQty);
    }

    [Fact]
    public async Task Merge_refuses_an_order_that_was_just_paid()
    {
        if (NoDb) return;
        var shop = await ShopAsync();
        var target = await OpenAsync(shop, "B1");
        var source = await OpenAsync(shop, "B2");
        // Máy khác vừa thu tiền bàn B2 — đơn đã hoàn tất, phiên chưa kịp đóng.
        await using (var db = Fx.NewDb())
            await db.PosSaleOrders.Where(o => o.Id == source.Order)
                .ExecuteUpdateAsync(x => x.SetProperty(o => o.Status, PosSaleOrderStatus.Completed));
        ActionResult<AppResponse<object>> r;
        await using (var db = Fx.NewDb())
            r = await Floor(db, shop.Store).MergeSession(target.Session,
                new PosSellIndustryController.MergeSessionDto(source.Session, Me));
        Assert.Contains("đã thanh toán", Error(r));
        await using var check = Fx.NewDb();
        Assert.Equal(PosSaleOrderStatus.Completed, (await check.PosSaleOrders.SingleAsync(o => o.Id == source.Order)).Status);
        Assert.Equal(source.Order, (await check.PosSaleOrderLines.SingleAsync(l => l.Id == source.Line)).SaleOrderId);
    }

    [Fact]
    public async Task Stale_cart_save_after_transfer_does_not_pull_the_order_back_to_the_old_table()
    {
        if (NoDb) return;
        var shop = await ShopAsync();
        var a = await OpenAsync(shop, "B1");
        var b = await TableAsync(shop, "B2");
        await using (var db = Fx.NewDb())
            Assert.Null(Error(await Floor(db, shop.Store).TransferSession(a.Session,
                new PosSellIndustryController.TransferSessionDto(b, Me))));

        // Máy khác còn mở bàn cũ: lưu nháp gửi bàn B1 + phiên cũ.
        await using (var db = Fx.NewDb())
            Data(await Sales(db, shop.Store).UpdateSale(a.Order, new PosSalesController.UpdateSaleDto(
                [new PosSalesController.SaleLineDto(shop.Product, 5, null, 50000, null, KitchenSentQty: 4)],
                0, 0, "Tiền mặt", null, null, null, ServiceResourceId: a.Resource, ResourceSessionId: a.Session)));
        await using var check = Fx.NewDb();
        Assert.Equal(b, (await check.PosSaleOrders.SingleAsync(o => o.Id == a.Order)).ServiceResourceId);
    }

    [Fact]
    public async Task Two_devices_moving_into_the_same_empty_table_only_one_wins()
    {
        if (NoDb) return;
        var shop = await ShopAsync();
        var a = await OpenAsync(shop, "B1");
        var c = await OpenAsync(shop, "B3");
        var empty = await TableAsync(shop, "B2");

        async Task<ActionResult<AppResponse<object>>> Move(Guid session, string device)
        {
            await using var db = Fx.NewDb();
            return await Floor(db, shop.Store).TransferSession(session,
                new PosSellIndustryController.TransferSessionDto(empty, device));
        }
        var results = await Task.WhenAll(Move(a.Session, "dev-1"), Move(c.Session, "dev-2"));
        Assert.Single(results, r => r.Result is OkObjectResult);
        Assert.Equal(1, await OpenSessionsOnAsync(empty));
    }

    [Fact]
    public async Task Delete_draft_is_refused_while_another_device_has_it_open()
    {
        if (NoDb) return;
        var shop = await ShopAsync();
        var a = await OpenAsync(shop, "B1", holder: OtherDeviceNow);
        await using (var db = Fx.NewDb())
            Assert.IsType<ConflictObjectResult>((await Sales(db, shop.Store).DeleteSale(a.Order, Me)).Result);
        await using (var db = Fx.NewDb())
            Assert.IsType<ConflictObjectResult>((await Sales(db, shop.Store).CancelDraftSale(a.Order, Me)).Result);
        await using var check = Fx.NewDb();
        Assert.Null((await check.PosSaleOrders.SingleAsync(o => o.Id == a.Order)).Deleted);
    }

    [Fact]
    public async Task Free_table_is_refused_while_another_device_just_opened_it()
    {
        if (NoDb) return;
        var shop = await ShopAsync();
        // Máy khác vừa mở bàn trống để gọi món (đơn tạm chưa có món, đang giữ khóa).
        var a = await OpenAsync(shop, "B1", qty: 0, sent: 0, done: 0, holder: OtherDeviceNow);
        await using (var db = Fx.NewDb())
            Assert.IsType<ConflictObjectResult>((await Floor(db, shop.Store).FreeResource(a.Resource, Me)).Result);
        Assert.Equal(1, await OpenSessionsOnAsync(a.Resource));

        // Máy đó đã thoát (khóa cũ) → trả bàn được.
        await using (var db = Fx.NewDb())
            await db.PosSaleOrders.Where(o => o.Id == a.Order)
                .ExecuteUpdateAsync(x => x.SetProperty(o => o.LockedAt, DateTime.UtcNow.AddMinutes(-3)));
        await using (var db = Fx.NewDb())
            Assert.IsType<OkObjectResult>((await Floor(db, shop.Store).FreeResource(a.Resource, Me)).Result);
        Assert.Equal(0, await OpenSessionsOnAsync(a.Resource));
    }

    [Fact]
    public async Task Guest_count_on_a_closed_session_is_rejected()
    {
        if (NoDb) return;
        var shop = await ShopAsync();
        var a = await OpenAsync(shop, "B1");
        await using (var db = Fx.NewDb())
            await db.PosResourceSessions.Where(s => s.Id == a.Session)
                .ExecuteUpdateAsync(x => x.SetProperty(s => s.Status, PosResourceSessionStatus.Closed));
        await using (var db = Fx.NewDb())
            Assert.Equal("Phiên đã đóng", Error(await Floor(db, shop.Store).SetGuestCount(a.Session,
                new PosSellIndustryController.GuestCountDto(5, Me))));
    }

    [Fact]
    public async Task Two_devices_sending_the_same_table_to_kitchen_print_it_once()
    {
        if (NoDb) return;
        var shop = await ShopAsync();
        var a = await OpenAsync(shop, "B1", qty: 3, sent: 0, done: 0);

        async Task<ActionResult<AppResponse<object>>> Send(string device)
        {
            await using var db = Fx.NewDb();
            return await Floor(db, shop.Store).KitchenSend(a.Session,
                new PosSellIndustryController.KitchenSendDto(DeviceId: device, RequestId: Guid.NewGuid().ToString("N")));
        }
        var results = await Task.WhenAll(Send("dev-1"), Send("dev-2"));
        var printed = results.Where(r => r.Result is OkObjectResult)
            .Sum(r => Json(r).GetProperty("sentQty").GetDecimal());
        Assert.Equal(3m, printed);
    }
}

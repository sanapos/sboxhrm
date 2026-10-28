using System.Text.Json;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Api.Services.PaymentGateway;
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

    [Fact]
    public async Task Merge_moves_deposit_and_discount_and_keeps_each_tables_pause_on_its_own_lines()
    {
        if (NoDb) return;
        var shop = await ShopAsync();
        var target = await OpenAsync(shop, "B1");
        var source = await OpenAsync(shop, "B2");
        var deposit = Guid.NewGuid();
        await using (var db = Fx.NewDb())
        {
            // Bàn nguồn: giảm 20.000, cọc đặt bàn 100.000 đã áp vào đơn, đã tạm dừng 15 phút. Bàn đích dừng 5 phút.
            await db.PosSaleOrders.Where(o => o.Id == source.Order).ExecuteUpdateAsync(x => x
                .SetProperty(o => o.Discount, 20000m).SetProperty(o => o.Total, 180000m));
            await db.PosResourceSessions.Where(s => s.Id == source.Session)
                .ExecuteUpdateAsync(x => x.SetProperty(s => s.AccumulatedPauseMinutes, 15));
            await db.PosResourceSessions.Where(s => s.Id == target.Session)
                .ExecuteUpdateAsync(x => x.SetProperty(s => s.AccumulatedPauseMinutes, 5));
            db.PosResourceReservations.Add(new PosResourceReservation
            {
                Id = deposit, StoreId = shop.Store, ResourceId = source.Resource, CustomerName = "Khách cọc",
                ReservedAt = DateTime.UtcNow.AddHours(-1), Status = PosResourceReservationStatus.Seated,
                DepositAmount = 100000, DepositPaid = 100000, DepositStatus = PosReservationDepositStatus.Applied,
                DepositAppliedOrderId = source.Order,
            });
            await db.SaveChangesAsync();
        }
        await using (var db = Fx.NewDb())
            Assert.Null(Error(await Floor(db, shop.Store).MergeSession(target.Session,
                new PosSellIndustryController.MergeSessionDto(source.Session, Me))));

        await using var check = Fx.NewDb();
        var merged = await check.PosSaleOrders.SingleAsync(o => o.Id == target.Order);
        Assert.Equal(20000m, merged.Discount);
        Assert.Equal(400000m - 20000m, merged.Total);
        Assert.Equal(target.Order, (await check.PosResourceReservations.SingleAsync(r => r.Id == deposit)).DepositAppliedOrderId);
        // Pause bàn nguồn không cộng vào phiên đích (trừ cả món bàn đích) — ghi vào món chuyển sang (15 − 5 trùng).
        Assert.Equal(5, (await check.PosResourceSessions.SingleAsync(s => s.Id == target.Session)).AccumulatedPauseMinutes);
        Assert.Equal(10, (await check.PosSaleOrderLines.SingleAsync(l => l.Id == source.Line)).ServicePauseMinutes);
        Assert.Equal(0, (await check.PosSaleOrderLines.SingleAsync(l => l.Id == target.Line)).ServicePauseMinutes);
        // Món bàn đích đã chốt giờ bắt đầu — không bị tính từ giờ mở bàn nguồn.
        Assert.NotNull((await check.PosSaleOrderLines.SingleAsync(l => l.Id == target.Line)).ServiceStartedAt);
        Assert.Equal(source.Resource,
            (await check.PosResourceSessions.SingleAsync(s => s.Id == target.Session)).MovedFromResourceId);
    }

    [Fact]
    public async Task Transfer_keeps_a_booking_for_later_tonight_on_the_target_table()
    {
        if (NoDb) return;
        var shop = await ShopAsync();
        var a = await OpenAsync(shop, "B1");
        var b = await TableAsync(shop, "B2");
        var tonight = Guid.NewGuid();
        var now = Guid.NewGuid();
        await using (var db = Fx.NewDb())
        {
            db.PosResourceReservations.Add(new PosResourceReservation
            {
                Id = tonight, StoreId = shop.Store, ResourceId = b, CustomerName = "Tối nay",
                ReservedAt = DateTime.UtcNow.AddHours(5), Status = PosResourceReservationStatus.Booked,
            });
            db.PosResourceReservations.Add(new PosResourceReservation
            {
                Id = now, StoreId = shop.Store, ResourceId = b, CustomerName = "Đến giờ",
                ReservedAt = DateTime.UtcNow.AddMinutes(10), Status = PosResourceReservationStatus.Booked,
            });
            await db.SaveChangesAsync();
        }
        await using (var db = Fx.NewDb())
        {
            var r = await Floor(db, shop.Store).TransferSession(a.Session,
                new PosSellIndustryController.TransferSessionDto(b, Me));
            Assert.Null(Error(r));
        }
        await using var check = Fx.NewDb();
        var kept = await check.PosResourceReservations.SingleAsync(r => r.Id == tonight);
        Assert.Equal(PosResourceReservationStatus.Booked, kept.Status);
        Assert.Null(kept.Deleted);
        Assert.Equal(PosResourceReservationStatus.Cancelled,
            (await check.PosResourceReservations.IgnoreQueryFilters().SingleAsync(r => r.Id == now)).Status);
        var moved = await check.PosResourceSessions.SingleAsync(s => s.Id == a.Session);
        Assert.Equal((b, a.Resource), (moved.ResourceId, moved.MovedFromResourceId));
    }

    static readonly IServiceProvider ApprovalServices = new ServiceCollection()
        .AddSingleton<IDataProtectionProvider>(new EphemeralDataProtectionProvider())
        .BuildServiceProvider();

    [Fact]
    public async Task Paid_split_bill_counts_toward_the_provisional_bill()
    {
        if (NoDb) return;
        var shop = await ShopAsync();
        var a = await OpenAsync(shop, "B1", qty: 6);   // 300.000
        Guid split;
        await using (var db = Fx.NewDb())
        {
            var s = await db.PosStoreSellSettings.AsTracking().FirstAsync(x => x.StoreId == shop.Store);
            s.AllowProvisionalBill = true;
            s.ExtraJson = "{\"afterBillApproval\":{\"enabled\":true}}";
            await db.PosResourceSessions.Where(x => x.Id == a.Session).ExecuteUpdateAsync(x => x
                .SetProperty(v => v.BillRequested, true)
                .SetProperty(v => v.BillRequestedAt, DateTime.UtcNow.AddMinutes(-5))
                .SetProperty(v => v.BillRequestedTotal, 500000m)
                .SetProperty(v => v.BillRequestCount, 1));
            // Bill tách (cùng bàn, không gắn phiên) đã thu 200.000.
            split = Guid.NewGuid();
            db.PosSaleOrders.Add(new PosSaleOrder
            {
                Id = split, StoreId = shop.Store, OrderNo = "HDT" + split.ToString("N")[..6],
                Status = PosSaleOrderStatus.Completed, SubTotal = 200000, Total = 200000,
                ServiceResourceId = a.Resource, SplitFromOrderId = a.Order, IsActive = true,
            });
            await db.SaveChangesAsync();
        }

        async Task<string?> Deny(Guid orderId)
        {
            await using var db = Fx.NewDb();
            var order = await db.PosSaleOrders.FirstAsync(o => o.Id == orderId);
            var http = new DefaultHttpContext { RequestServices = ApprovalServices };
            return await PosAfterBillApproval.DenyPaymentBelowBillAsync(db, http, shop.Store, order, "Cashier");
        }

        // 300.000 + bill tách 200.000 = đủ tạm tính 500.000 (trước đây bị đòi duyệt).
        Assert.Null(await Deny(a.Order));
        // Bill tách chưa thu → chưa so tổng.
        await using (var db = Fx.NewDb())
            await db.PosSaleOrders.Where(o => o.Id == split)
                .ExecuteUpdateAsync(x => x.SetProperty(o => o.Status, PosSaleOrderStatus.Draft));
        Assert.Null(await Deny(a.Order));
        // Không có bill tách nào: thu 300.000 < 500.000 → vẫn đòi duyệt.
        await using (var db = Fx.NewDb())
            await db.PosSaleOrders.Where(o => o.Id == split)
                .ExecuteUpdateAsync(x => x.SetProperty(o => o.Deleted, DateTime.UtcNow));
        Assert.NotNull(await Deny(a.Order));
    }

    static PosTingeePaidOrderService Tingee(ZKTecoDbContext db) => new(
        db, null!, new ZKTecoADMS.Api.Services.EInvoice.PosEInvoiceAutoIssuer(null!,
            NullLogger<ZKTecoADMS.Api.Services.EInvoice.PosEInvoiceAutoIssuer>.Instance),
        NullLogger<PosTingeePaidOrderService>.Instance);

    [Fact]
    public async Task Transfer_money_for_a_table_that_was_split_is_left_to_the_cashier()
    {
        if (NoDb) return;
        var shop = await ShopAsync();
        var a = await OpenAsync(shop, "B1", qty: 3, sent: 3, done: 0);   // QR in 150.000
        await using (var db = Fx.NewDb())
            Data(await Floor(db, shop.Store).SplitBill(a.Session, new PosSellIndustryController.SplitBillDto
            {
                Items = [new PosSellIndustryController.SplitBillItemDto { LineId = a.Line, Qty = 1 }],
                DeviceId = Me,
            }));
        string? msg;
        await using (var db = Fx.NewDb())
            msg = await Tingee(db).TryFulfillConfirmedIntentAsync(new PosTransferPaymentIntent
            {
                Id = Guid.NewGuid(), StoreId = shop.Store, SaleOrderId = a.Order, AmountExpected = 150000,
                ExternalOrderId = "x",
            }, 150000, null, null!);
        Assert.Contains("tách hóa đơn", msg);
        Assert.Equal(PosSaleOrderStatus.Draft, (await OrderAsync(a.Order)).Status);
    }

    [Fact]
    public async Task Transfer_money_for_a_merged_table_points_to_the_merged_order()
    {
        if (NoDb) return;
        var shop = await ShopAsync();
        var target = await OpenAsync(shop, "B1");
        var source = await OpenAsync(shop, "B2");
        await using (var db = Fx.NewDb())
            Assert.Null(Error(await Floor(db, shop.Store).MergeSession(target.Session,
                new PosSellIndustryController.MergeSessionDto(source.Session, Me))));
        var targetNo = (await OrderAsync(target.Order)).OrderNo;
        string? msg;
        await using (var db = Fx.NewDb())
            msg = await Tingee(db).TryFulfillConfirmedIntentAsync(new PosTransferPaymentIntent
            {
                Id = Guid.NewGuid(), StoreId = shop.Store, SaleOrderId = source.Order, AmountExpected = 200000,
                ExternalOrderId = "y",
            }, 200000, null, null!);
        Assert.Contains("gộp vào đơn " + targetNo, msg);
    }
}

using Microsoft.AspNetCore.DataProtection;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Xunit;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Tests.Pos;

/// <summary>
/// «Sau tạm tính cần quản lý duyệt»: chỉ có tác dụng khi bật cả «Cho phép tạm tính» lẫn tùy chọn này; nhân viên bị
/// chặn hủy món / hủy đơn / thu ít hơn tạm tính; quản lý làm được; mã duyệt đúng cửa hàng thì cho qua.
/// </summary>
[Collection("pos-pg")]
public class PosAfterBillApprovalTests(PosPgFixture fx) : PosFlowTestBase(fx)
{
    static readonly IServiceProvider Services = new ServiceCollection()
        .AddSingleton<IDataProtectionProvider>(new EphemeralDataProtectionProvider())
        .BuildServiceProvider();

    static T Ctl<T>(T c, Guid store, string role, string? token = null) where T : ControllerBase
    {
        PosPgFixture.As(c, store, role);
        c.HttpContext.RequestServices = Services;
        if (token != null) c.HttpContext.Request.Headers[PosAfterBillApproval.Header] = token;
        return c;
    }

    record Table(Guid Store, Guid Resource, Guid Session, Guid Order);

    async Task<Table> SetupAsync(bool allowProvisional, bool approval, decimal total = 500_000, bool billed = true)
    {
        var store = await Fx.NewStoreAsync();
        var area = Guid.NewGuid();
        var table = Guid.NewGuid();
        var session = Guid.NewGuid();
        var order = Guid.NewGuid();
        var product = (await Fx.AddProductAsync(store, "Lẩu thái", PosProductType.Goods, 100, 100_000, 250_000)).Id;
        await using var db = Fx.NewDb();
        var s = await db.PosStoreSellSettings.AsTracking().FirstOrDefaultAsync(x => x.StoreId == store);
        if (s == null)
        {
            s = new PosStoreSellSettings { Id = Guid.NewGuid(), StoreId = store, IsActive = true };
            db.PosStoreSellSettings.Add(s);
        }
        s.AllowProvisionalBill = allowProvisional;
        s.ExtraJson = approval ? "{\"afterBillApproval\":{\"enabled\":true}}" : null;
        db.PosServiceAreas.Add(new PosServiceArea { Id = area, StoreId = store, Name = "Tầng 1" });
        db.PosServiceResources.Add(new PosServiceResource { Id = table, StoreId = store, AreaId = area, Code = "B1", Name = "Bàn 1" });
        db.PosResourceSessions.Add(new PosResourceSession
        {
            Id = session, StoreId = store, ResourceId = table, StartedAt = DateTime.UtcNow.AddMinutes(-40),
            Status = PosResourceSessionStatus.Open, BillRequested = billed,
            BillRequestedAt = billed ? DateTime.UtcNow.AddMinutes(-5) : null,
            BillRequestedTotal = billed ? total : null, BillRequestCount = billed ? 1 : 0,
        });
        db.PosSaleOrders.Add(new PosSaleOrder
        {
            Id = order, StoreId = store, OrderNo = "T-" + order.ToString("N")[..6], Status = PosSaleOrderStatus.Draft,
            SubTotal = total, Total = total, ResourceSessionId = session, ServiceResourceId = table,
            Lines = [new PosSaleOrderLine
            {
                Id = Guid.NewGuid(), StoreId = store, ProductId = product, ProductName = "Lẩu thái", Qty = 2,
                UnitPrice = total / 2, LineTotal = total,
            }],
        });
        await db.SaveChangesAsync();
        return new Table(store, table, session, order);
    }

    static PosSellIndustryController.KitchenVoidBatchDto Void(Table t) => new(
        [new PosSellIndustryController.KitchenVoidLineDto(null, "Lẩu thái", 1)],
        SaleOrderId: t.Order, ResourceSessionId: t.Session, ServiceResourceId: t.Resource, ResourceName: "Bàn 1",
        Reason: "Khách đổi ý");

    /// <summary>Bị từ chối với câu «Cần quản lý duyệt…».</summary>
    static bool NeedsApproval<TR>(ActionResult<TR> r) =>
        r.Result is BadRequestObjectResult { Value: { } v }
        && v.GetType().GetProperty("Message")?.GetValue(v) is string m
        && m.StartsWith(PosAfterBillApproval.DeniedPrefix);

    [Fact]
    public void Setting_needs_provisional_bill_on()
    {
        const string on = "{\"afterBillApproval\":{\"enabled\":true}}";
        Assert.True(PosAfterBillApproval.Enabled(new PosStoreSellSettings { AllowProvisionalBill = true, ExtraJson = on }));
        Assert.False(PosAfterBillApproval.Enabled(new PosStoreSellSettings { AllowProvisionalBill = false, ExtraJson = on }));
        Assert.False(PosAfterBillApproval.Enabled(new PosStoreSellSettings { AllowProvisionalBill = true, ExtraJson = "{}" }));
        Assert.False(PosAfterBillApproval.Enabled(new PosStoreSellSettings { AllowProvisionalBill = true, ExtraJson = "x{" }));
    }

    [Fact]
    public void Token_is_bound_to_store()
    {
        var a = Guid.NewGuid();
        var token = PosAfterBillApproval.Issue(Services, a, "chu@q.vn");
        Assert.Equal("chu@q.vn", PosAfterBillApproval.Validate(Services, a, token));
        Assert.Null(PosAfterBillApproval.Validate(Services, Guid.NewGuid(), token));
        Assert.Null(PosAfterBillApproval.Validate(Services, a, token + "x"));
        Assert.Null(PosAfterBillApproval.Validate(Services, a, null));
    }

    [Fact]
    public async Task Cashier_kitchen_void_after_bill_needs_approval_token()
    {
        if (NoDb) return;
        var t = await SetupAsync(allowProvisional: true, approval: true);
        await using (var db = Fx.NewDb())
            Assert.True(NeedsApproval(await Ctl(new PosSellIndustryController(db, null!, null!, null!), t.Store, "Cashier")
                .CreateKitchenVoids(Void(t))));
        var token = PosAfterBillApproval.Issue(Services, t.Store, "chu@q.vn");
        await using (var db = Fx.NewDb())
            Assert.NotNull(Data(await Ctl(new PosSellIndustryController(db, null!, null!, null!), t.Store, "Cashier", token)
                .CreateKitchenVoids(Void(t))));
        await using (var db = Fx.NewDb())
        {
            var audit = await db.PosCancelReturnAudits.SingleAsync(a => a.StoreId == t.Store);
            Assert.Contains("Quản lý duyệt: chu@q.vn", audit.DetailNote);
            Assert.True(audit.AfterProvisionalBill);
        }
    }

    [Fact]
    public async Task Manager_and_disabled_store_are_not_blocked()
    {
        if (NoDb) return;
        var t = await SetupAsync(allowProvisional: true, approval: true);
        await using (var db = Fx.NewDb())
            Assert.NotNull(Data(await Ctl(new PosSellIndustryController(db, null!, null!, null!), t.Store, "Manager")
                .CreateKitchenVoids(Void(t))));
        var off = await SetupAsync(allowProvisional: false, approval: true);
        await using (var db = Fx.NewDb())
            Assert.NotNull(Data(await Ctl(new PosSellIndustryController(db, null!, null!, null!), off.Store, "Cashier")
                .CreateKitchenVoids(Void(off))));
        var notBilled = await SetupAsync(allowProvisional: true, approval: true, billed: false);
        await using (var db = Fx.NewDb())
            Assert.NotNull(Data(await Ctl(new PosSellIndustryController(db, null!, null!, null!), notBilled.Store, "Cashier")
                .CreateKitchenVoids(Void(notBilled))));
    }

    [Fact]
    public async Task Cashier_cannot_cancel_draft_after_bill()
    {
        if (NoDb) return;
        var t = await SetupAsync(allowProvisional: true, approval: true);
        await using (var db = Fx.NewDb())
            Assert.True(NeedsApproval(await Ctl(Sales(db, t.Store), t.Store, "Cashier").CancelDraftSale(t.Order)));
        await using (var db = Fx.NewDb())
            Assert.Equal(PosSaleOrderStatus.Draft, (await db.PosSaleOrders.SingleAsync(o => o.Id == t.Order)).Status);
    }

    [Fact]
    public async Task Paying_less_than_provisional_bill_needs_approval()
    {
        if (NoDb) return;
        // Tạm tính in 500k, đơn giờ chỉ còn 300k.
        var t = await SetupAsync(allowProvisional: true, approval: true, total: 300_000);
        await using (var db = Fx.NewDb())
        {
            var s = await db.PosResourceSessions.AsTracking().SingleAsync(x => x.Id == t.Session);
            s.BillRequestedTotal = 500_000;
            await db.SaveChangesAsync();
        }
        await using (var db = Fx.NewDb())
        {
            var http = Ctl(Sales(db, t.Store), t.Store, "Cashier").HttpContext;
            var order = await db.PosSaleOrders.SingleAsync(o => o.Id == t.Order);
            var err = await PosAfterBillApproval.DenyPaymentBelowBillAsync(db, http, t.Store, order, "Cashier");
            Assert.StartsWith(PosAfterBillApproval.DeniedPrefix, err);
            Assert.Contains("300.000đ", err);
            Assert.Contains("500.000đ", err);
            // Quản lý / có mã duyệt → được thu.
            Assert.Null(await PosAfterBillApproval.DenyPaymentBelowBillAsync(db, http, t.Store, order, "Manager"));
            http.Request.Headers[PosAfterBillApproval.Header] = PosAfterBillApproval.Issue(Services, t.Store, "chu@q.vn");
            Assert.Null(await PosAfterBillApproval.DenyPaymentBelowBillAsync(db, http, t.Store, order, "Cashier"));
        }
        // Thu đủ tạm tính → không chặn.
        var ok = await SetupAsync(allowProvisional: true, approval: true, total: 500_000);
        await using (var db = Fx.NewDb())
            Assert.Null(PosAfterBillApproval.DenyPaymentBelowBillAsync(db, Ctl(Sales(db, ok.Store), ok.Store, "Cashier").HttpContext,
                ok.Store, await db.PosSaleOrders.SingleAsync(o => o.Id == ok.Order), "Cashier").Result);
    }
}

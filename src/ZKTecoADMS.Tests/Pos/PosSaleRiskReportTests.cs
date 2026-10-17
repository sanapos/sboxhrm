using Microsoft.EntityFrameworkCore;
using Xunit;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using R = ZKTecoADMS.Api.Services.PosSaleRiskReportBuilder;

namespace ZKTecoADMS.Tests.Pos;

/// <summary>«Nguy cơ gian lận»: giảm / hủy sau tạm tính, đá bill, đá món, hủy đơn đã thu, không in, in lại, giảm giá.</summary>
public class PosSaleRiskReportTests
{
    static readonly DateTime From = new(2026, 10, 10, 17, 0, 0, DateTimeKind.Utc); // 00:00 VN 11/10
    static readonly DateTime To = From.AddDays(7);
    static readonly DateTime T = From.AddDays(2).AddHours(5);                       // 12:00 VN 13/10
    static readonly Dictionary<string, string> Names = new() { ["an@q.vn"] = "Nguyễn An", ["binh@q.vn"] = "Trần Bình" };

    static R.OrderRow Order(string no, decimal total, string cashier = "an@q.vn", int print = 1, string pm = "Tiền mặt",
        Guid? session = null, decimal discount = 0, decimal? sub = null, DateTime? at = null,
        PosSaleOrderStatus status = PosSaleOrderStatus.Completed, Guid? id = null) =>
        new(id ?? Guid.NewGuid(), no, status, at ?? T, sub ?? total + discount, discount, total, pm, print, cashier, null,
            session, "Bàn 5", "None");

    static PosCancelReturnAudit Audit(string type, decimal amount, bool afterBill = false, Guid? orderId = null,
        string actor = "an@q.vn", string? product = "Bia Tiger", DateTime? at = null, Guid? session = null) => new()
    {
        Id = Guid.NewGuid(), ActionType = type, Amount = amount, AfterProvisionalBill = afterBill, SaleOrderId = orderId,
        OrderNo = orderId == null ? null : "HD1", Actor = actor, ProductName = product, Qty = 1,
        OccurredAt = at ?? T.AddMinutes(10), ResourceName = "Bàn 5", ResourceSessionId = session,
    };

    static R.Report Build(List<R.OrderRow>? orders = null, List<R.SessionRow>? sessions = null,
        List<PosCancelReturnAudit>? audits = null) =>
        R.Build(orders ?? [], sessions ?? [], audits ?? [], Names, From, To);

    [Fact]
    public void Clean_period_is_green()
    {
        var r = Build([Order("HD1", 100_000), Order("HD2", 250_000)]);
        Assert.Equal("green", r.Verdict);
        Assert.Empty(r.Orders);
        Assert.Equal(7, r.Daily.Count);
    }

    [Fact]
    public void Paid_less_than_provisional_bill_is_high_with_missing_amount()
    {
        var s = Guid.NewGuid();
        var r = Build([Order("HD1", 300_000, session: s)],
            [new(s, "Bàn 5", PosResourceSessionStatus.Closed, T.AddMinutes(-20), 500_000, "binh@q.vn", 2)]);
        Assert.Equal("red", r.Verdict);
        var o = Assert.Single(r.Orders);
        Assert.Equal("high", o.Level);
        Assert.Equal(200_000, o.AmountAtRisk);
        Assert.Equal(500_000, o.ProvisionalTotal);
        Assert.Contains("REDUCED_AFTER_BILL", o.Flags.Select(f => f.Code));
        Assert.Contains("Nguyễn An", o.Staff);   // người thu
        Assert.Contains("Trần Bình", o.Staff);   // người in tạm tính
        Assert.Equal(200_000, r.Summary.ReducedAfterBillAmount);
    }

    [Fact]
    public void Paying_full_provisional_or_rounding_is_not_flagged()
    {
        var s = Guid.NewGuid();
        var r = Build([Order("HD1", 499_500, session: s)],
            [new(s, "Bàn 5", PosResourceSessionStatus.Closed, T.AddMinutes(-20), 500_000, "an@q.vn", 1)]);
        Assert.Equal("green", r.Verdict);
    }

    [Fact]
    public void Provisional_bill_then_closed_without_payment_is_high()
    {
        var s = Guid.NewGuid();
        var r = Build([], [new(s, "Bàn 7", PosResourceSessionStatus.Closed, T, 420_000, "an@q.vn", 1)]);
        var o = Assert.Single(r.Orders);
        Assert.Equal("UNPAID_AFTER_BILL", o.Flags[0].Code);
        Assert.Equal("high", o.Level);
        Assert.Equal(420_000, o.AmountAtRisk);
    }

    [Fact]
    public void Voids_after_provisional_bill_are_grouped_per_order()
    {
        var id = Guid.NewGuid();
        var r = Build([Order("HD1", 200_000, id: id)], audits:
        [
            Audit(PosCancelAuditHelper.KitchenVoid, 30_000, afterBill: true, orderId: id),
            Audit(PosCancelAuditHelper.KitchenVoid, 45_000, afterBill: true, orderId: id, product: "Mực nướng"),
        ]);
        var o = Assert.Single(r.Orders);
        var f = Assert.Single(o.Flags, x => x.Code == "VOID_AFTER_BILL");
        Assert.Equal(75_000, f.Amount);
        Assert.Contains("hủy 2 món", f.Detail);
        Assert.Contains("camera", o.HowToCheck);
    }

    [Fact]
    public void Dropped_bill_and_paid_cash_cancel_are_flagged()
    {
        var paid = Guid.NewGuid();
        var r = Build([Order("HD9", 180_000, id: paid, at: T.AddMinutes(-30))], audits:
        [
            Audit(PosCancelAuditHelper.DraftCancel, 260_000, session: Guid.NewGuid()),
            Audit(PosCancelAuditHelper.SaleCancel, 180_000, orderId: paid),
        ]);
        Assert.Contains(r.Orders, o => o.Flags.Any(f => f.Code == "DROPPED_BILL" && f.Level == "medium"));
        var c = Assert.Single(r.Orders, o => o.Flags.Any(f => f.Code == "CANCEL_PAID"));
        Assert.Equal("high", c.Level); // tiền mặt
        Assert.Contains("40 phút sau khi bán", c.Flags[0].Detail);
    }

    [Fact]
    public void Many_kitchen_voids_on_one_order_is_dropping_items()
    {
        var id = Guid.NewGuid();
        var r = Build([Order("HD1", 100_000, id: id)], audits:
            Enumerable.Range(0, 3).Select(_ => Audit(PosCancelAuditHelper.KitchenVoid, 20_000, orderId: id)).ToList());
        Assert.Contains(r.Orders, o => o.Flags.Any(f => f.Code == "MANY_VOIDS"));
        // Một món hủy lẻ không bị liệt kê.
        var single = Build([Order("HD1", 100_000, id: id)], audits: [Audit(PosCancelAuditHelper.KitchenVoid, 20_000, orderId: id)]);
        Assert.Empty(single.Orders);
    }

    [Fact]
    public void Quick_return_by_same_staff_is_flagged()
    {
        var id = Guid.NewGuid();
        var r = Build([Order("HD1", 150_000, id: id, at: T.AddHours(-1))],
            audits: [Audit(PosCancelAuditHelper.SaleReturn, 150_000, orderId: id)]);
        var f = Assert.Single(r.Orders.SelectMany(o => o.Flags));
        Assert.Equal("QUICK_RETURN", f.Code);
        Assert.Contains("cùng người bán và người trả", f.Detail);
    }

    [Fact]
    public void Big_discount_and_reprints_are_medium()
    {
        var r = Build([Order("HD1", 300_000, discount: 200_000), Order("HD2", 90_000, print: 4)]);
        Assert.Equal("yellow", r.Verdict);
        Assert.Contains(r.Orders, o => o.Flags.Any(f => f.Code == "BIG_DISCOUNT"));
        Assert.Contains(r.Orders, o => o.Flags.Any(f => f.Code == "REPRINT"));
    }

    [Fact]
    public void Staff_who_skips_receipts_much_more_than_store_is_highlighted()
    {
        // Cả quán in gần hết; Bình 6/8 đơn tiền mặt không in.
        var orders = Enumerable.Range(0, 20).Select(i => Order($"A{i}", 50_000)).ToList();
        orders.AddRange(Enumerable.Range(0, 8).Select(i => Order($"B{i}", 50_000, "binh@q.vn", print: i < 6 ? 0 : 1)));
        var r = Build(orders);
        var binh = Assert.Single(r.Staff, s => s.Name == "Trần Bình");
        Assert.Equal("yellow", binh.Level);
        Assert.Equal(6, binh.NoReceipt);
        Assert.Contains(binh.Notes, n => n.StartsWith("Không in hóa đơn"));
        Assert.Equal("green", r.Staff.Single(s => s.Name == "Nguyễn An").Level);
        Assert.Equal(6, r.Orders.Count(o => o.Flags.Any(f => f.Code == "NO_RECEIPT")));
    }

    [Fact]
    public void Store_that_never_prints_does_not_list_every_order()
    {
        var r = Build(Enumerable.Range(0, 15).Select(i => Order($"A{i}", 50_000, print: 0)).ToList());
        Assert.Empty(r.Orders);
        Assert.Equal(100, r.Summary.NoReceiptPct);
        // Không liệt kê từng đơn nhưng vẫn gợi ý luôn in hóa đơn.
        Assert.Contains(r.Recommendations, x => x.Title == "Luôn in hóa đơn cho khách");
    }

    [Fact]
    public void Card_payment_cancel_is_medium_and_staff_red_on_repeated_high()
    {
        var a = Guid.NewGuid();
        var b = Guid.NewGuid();
        var r = Build([Order("HD1", 100_000, id: a, pm: "Chuyển khoản"), Order("HD2", 700_000, id: b)],
            audits:
            [
                Audit(PosCancelAuditHelper.SaleCancel, 100_000, orderId: a),
                Audit(PosCancelAuditHelper.SaleCancel, 700_000, orderId: b),
            ]);
        Assert.Equal("medium", r.Orders.Single(o => o.OrderId == a).Level);
        Assert.Equal("red", r.Staff.Single(s => s.Name == "Nguyễn An").Level);
        Assert.Contains(r.Recommendations, x => x.Title.Contains("hủy hóa đơn đã thu"));
    }
}

/// <summary>In tạm tính lưu số tiền lớn nhất + thời điểm (cần CSDL).</summary>
[Collection("pos-pg")]
public class PosProvisionalBillSnapshotTests(PosPgFixture fx) : PosFlowTestBase(fx)
{
    [Fact]
    public async Task Request_bill_snapshots_highest_printed_total()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var area = Guid.NewGuid();
        var table = Guid.NewGuid();
        var session = Guid.NewGuid();
        var order = Guid.NewGuid();
        await using (var db = Fx.NewDb())
        {
            var s = await db.PosStoreSellSettings.FirstOrDefaultAsync(x => x.StoreId == store);
            if (s == null)
            {
                s = new PosStoreSellSettings { Id = Guid.NewGuid(), StoreId = store, IsActive = true };
                db.PosStoreSellSettings.Add(s);
            }
            s.AllowProvisionalBill = true;
            db.PosServiceAreas.Add(new PosServiceArea { Id = area, StoreId = store, Name = "Tầng 1" });
            db.PosServiceResources.Add(new PosServiceResource { Id = table, StoreId = store, AreaId = area, Code = "B5", Name = "Bàn 5" });
            db.PosResourceSessions.Add(new PosResourceSession
            {
                Id = session, StoreId = store, ResourceId = table, StartedAt = DateTime.UtcNow.AddMinutes(-30),
                Status = PosResourceSessionStatus.Open,
            });
            db.PosSaleOrders.Add(new PosSaleOrder
            {
                Id = order, StoreId = store, OrderNo = "T-1", Status = PosSaleOrderStatus.Draft, SubTotal = 500_000,
                Total = 500_000, ResourceSessionId = session, ServiceResourceId = table,
            });
            await db.SaveChangesAsync();
        }
        PosSellIndustryController Ctl(ZKTecoADMS.Infrastructure.ZKTecoDbContext db) =>
            PosPgFixture.As(new PosSellIndustryController(db, null!, null!, null!), store);

        await using (var db = Fx.NewDb())
            Assert.NotNull(Data(await Ctl(db).RequestBillByResource(table)));
        // Bớt món còn 300k rồi in lại → giữ số lớn nhất đã đưa khách (500k).
        await using (var db = Fx.NewDb())
        {
            var o = await db.PosSaleOrders.AsTracking().SingleAsync(x => x.Id == order);
            o.Total = 300_000;
            await db.SaveChangesAsync();
        }
        await using (var db = Fx.NewDb())
            Assert.NotNull(Data(await Ctl(db).RequestBill(session)));

        await using (var db = Fx.NewDb())
        {
            var s = await db.PosResourceSessions.SingleAsync(x => x.Id == session);
            Assert.Equal(500_000, s.BillRequestedTotal);
            Assert.Equal(2, s.BillRequestCount);
            Assert.NotNull(s.BillRequestedAt);
        }
    }
}

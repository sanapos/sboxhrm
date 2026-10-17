using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Xunit;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Tests.Pos;

/// <summary>Báo cáo nhân viên: tiền két ca thu ngân, tổng kết ca, cuối ngày không đổi khi khách trả nợ sau, lọc theo người bán.</summary>
[Collection("pos-pg")]
public class PosStaffReportsTests(PosPgFixture fx) : PosFlowTestBase(fx)
{
    static object? P(object o, string name) => o.GetType().GetProperty(name)?.GetValue(o);
    static decimal N(object o, string name) => Convert.ToDecimal(P(o, name) ?? 0m);
    static List<object> L(object o, string name) => ((System.Collections.IEnumerable)P(o, name)!).Cast<object>().ToList();
    static DateTime VnToday => DateTime.UtcNow.AddHours(7).Date;

    async Task<PosSalesController.SaleOrderDto> SellAsync(Guid store, Guid pid, decimal price, Guid? customerId = null,
        string? soldBy = null, params (decimal Amount, string Method)[] pays)
    {
        await using var db = Fx.NewDb();
        var dto = new PosSalesController.CreateSaleDto(
            [new PosSalesController.SaleLineDto(pid, 1, null, price, null)],
            0, pays.Sum(p => p.Amount), pays.Length == 0 ? "Tiền mặt" : pays[0].Method, null, customerId, null,
            SoldBy: soldBy,
            Payments: pays.Length == 0 ? null : [.. pays.Select(p => new PosSalesController.SalePaymentInputDto(p.Amount, p.Method))]);
        return Data(await Sales(db, store).CreateSale(dto));
    }

    [Fact]
    public async Task Ca_thu_ngan_tien_ket_theo_phieu_thu_chi_va_tong_ket_ca()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var tra = await Fx.AddProductAsync(store, "Trà", PosProductType.Goods, 100, 1000, 50000);
        await using (var db = Fx.NewDb())
        {
            db.PosStoreSellSettings.Add(new PosStoreSellSettings { Id = Guid.NewGuid(), StoreId = store, EnableCashierShift = true, IsActive = true });
            await db.SaveChangesAsync();
        }
        Guid shiftId;
        await using (var db = Fx.NewDb())
        {
            var r = Data(await PosPgFixture.As(new PosCashierShiftsController(db), store)
                .Open(new PosCashierShiftsController.OpenShiftDto { OpeningCash = 100000 }));
            shiftId = (Guid)P(P(r, "shift")!, "Id")!;
        }
        await SellAsync(store, tra.Id, 50000, pays: (50000, "Tiền mặt"));
        await SellAsync(store, tra.Id, 50000, pays: [(30000, "Tiền mặt"), (20000, "Chuyển khoản")]);
        var c = await SellAsync(store, tra.Id, 50000, pays: (50000, "Tiền mặt"));
        await ReturnAsync(store, c.Id, (tra.Id, 1));

        await using (var db = Fx.NewDb())
        {
            var r = Data(await PosPgFixture.As(new PosCashierShiftsController(db), store)
                .Close(shiftId, new PosCashierShiftsController.CloseShiftDto { CountedCash = 180000 }));
            var s = P(r, "shift")!;
            // Két: 100 đầu ca + 50 + 30 (phần tiền mặt của đơn trả kết hợp) + 50 − 50 hoàn = 180.
            // Trước đây 150 (bỏ cả đơn «Tiền mặt + Chuyển khoản») → báo thừa 30.000 dù két đúng.
            Assert.Equal(180000m, N(s, "ExpectedCash"));
            Assert.Equal(0m, N(s, "Difference"));
        }

        await using (var db = Fx.NewDb())
        {
            var sum = Data(await Reports(db, store).GetCashierShiftSummary(shiftId));
            Assert.Equal(130000m, N(sum, "saleCash"));
            Assert.Equal(50000m, N(sum, "refundCash"));
            Assert.Equal(180000m, N(sum, "expectedCash"));
            Assert.Equal(3m, N(sum, "orderCount"));
            var pays = L(sum, "payments").ToDictionary(p => (string)P(p, "paymentMethod")!, p => N(p, "total"));
            Assert.Equal(130000m, pays["Tiền mặt"]);
            Assert.Equal(20000m, pays["Chuyển khoản"]);
            Assert.Equal(2m, N(L(sum, "products").Single(), "qty")); // 3 ly − 1 ly khách trả
        }
    }

    [Fact]
    public async Task Cuoi_ngay_thuc_thu_va_cong_no_khong_doi_khi_khach_tra_no_ngay_sau()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var gao = await Fx.AddProductAsync(store, "Gạo", PosProductType.Goods, 100, 1000, 100000);
        var cust = new PosCustomer { Id = Guid.NewGuid(), StoreId = store, CustomerCode = "KH1", Name = "Khách nợ", IsActive = true };
        await using (var db = Fx.NewDb()) { db.PosCustomers.Add(cust); await db.SaveChangesAsync(); }
        await SellAsync(store, gao.Id, 100000, cust.Id, pays: (40000, "Tiền mặt"));

        async Task<(decimal received, decimal debt)> Eod()
        {
            await using var db = Fx.NewDb();
            var e = Data(await Reports(db, store).GetEndOfDay(VnToday, VnToday, null, null, includeProductDetail: false));
            return (N(e, "actualReceived"), N(e, "debtTotal"));
        }
        Assert.Equal((40000m, 60000m), await Eod());
        await using (var db = Fx.NewDb())
        {
            var c = await db.PosCustomers.AsTracking().FirstAsync(x => x.Id == cust.Id);
            var (_, err) = await PosCustomerFinanceHelper.CollectDebtAsync(db, store, c, 60000, "Tiền mặt",
                DateTime.UtcNow.AddDays(2), null, null, "test@sbox.vn");
            Assert.Null(err);
            await db.SaveChangesAsync();
        }
        // Trước đây xem lại ngày bán: thực thu 100.000, công nợ 0 → lệch phiếu cuối ngày đã in.
        Assert.Equal((40000m, 60000m), await Eod());
    }

    [Fact]
    public async Task Loc_theo_nguoi_ban_dung_nguoi_khong_dung_chua_ten_va_hang_ban_theo_nhan_vien()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var tra = await Fx.AddProductAsync(store, "Trà", PosProductType.Goods, 100, 10000, 30000);
        var cafe = await Fx.AddProductAsync(store, "Cà phê", PosProductType.Goods, 100, 8000, 25000);
        await SellAsync(store, tra.Id, 30000, soldBy: "An", pays: (30000, "Tiền mặt"));
        await SellAsync(store, tra.Id, 30000, soldBy: "An", pays: (30000, "Tiền mặt"));
        await SellAsync(store, cafe.Id, 25000, soldBy: "Lan", pays: (25000, "Tiền mặt"));

        await using var db = Fx.NewDb();
        var r = Reports(db, store);
        var staff = L(Data(await r.GetStaffSummary(VnToday, VnToday)), "staff");
        Assert.Equal(2, staff.Count);
        var an = staff.Single(s => (string)P(s, "soldBy")! == "An");
        Assert.Equal(2m, N(an, "orderCount"));
        Assert.Equal(60000m, N(an, "revenue"));
        Assert.Equal(40000m, N(an, "profit"));
        Assert.Equal(30000m, N(an, "avgOrder"));

        // Trước đây lọc «An» theo «chứa» → ra cả đơn của «Lan».
        var orders = Data(await r.GetSalesOrders(VnToday, VnToday, staffKey: "n:An"));
        Assert.Equal(2m, N(orders, "total"));
        var goods = L(Data(await r.GetGoodsSummary(VnToday, VnToday, staffKey: "n:Lan")), "topByRevenue");
        Assert.Equal("Cà phê", (string)P(goods.Single(), "productName")!);
    }

    [Fact]
    public async Task Cuoi_ngay_loc_don_chua_gan_nhan_vien()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var tra = await Fx.AddProductAsync(store, "Trà", PosProductType.Goods, 100, 1000, 30000);
        await SellAsync(store, tra.Id, 30000, pays: (30000, "Tiền mặt"));
        await using var db = Fx.NewDb();
        var r = Reports(db, store);
        var list = ((System.Collections.IEnumerable)Data(await r.GetEndOfDayStaff(VnToday, VnToday))).Cast<object>().ToList();
        Assert.Contains(list, x => (Guid?)P(x, "employeeId") == Guid.Empty);
        var e = Data(await r.GetEndOfDay(VnToday, VnToday, null, Guid.Empty, includeProductDetail: false));
        Assert.Equal(1m, N(e, "orderCount"));
    }
}

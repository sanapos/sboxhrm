using Microsoft.AspNetCore.Mvc;
using Xunit;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Tests.Pos;

/// <summary>
/// Số liệu tính tay:
/// HĐ1 tiền mặt: 2 Trà sữa × 25.000 + 2 Bánh × 15.000 = 80.000, giảm đơn 5.000 → 75.000, thu đủ.
///   Khách trả 1 Bánh: hoàn 15.000 − 5.000×15/80 = 14.062,5 → 14.063 (tiền mặt) → HĐ1 còn 60.937.
/// HĐ2 Chị Hoa chuyển khoản: 4 Trà sữa × 25.000 giảm dòng 10.000 = 90.000, trả 50.000, nợ 40.000;
///   cùng ngày trả nợ 30.000 tiền mặt.
/// Doanh thu thuần 150.937 · Giảm giá 15.000 · Thu khi bán 125.000 (TM 75.000 + CK 50.000).
/// Tiền mặt két = 75.000 − 14.063 + 30.000 = 90.937.
/// </summary>
[Collection("pos-pg")]
public class PosReportCashAndDiscountTests(PosPgFixture fx) : PosFlowTestBase(fx)
{
    static decimal N(object o, string name) =>
        Convert.ToDecimal(o.GetType().GetProperty(name)?.GetValue(o)
                          ?? throw new Xunit.Sdk.XunitException($"Thiếu trường {name}"));

    static object P(object o, string name) =>
        o.GetType().GetProperty(name)?.GetValue(o) ?? throw new Xunit.Sdk.XunitException($"Thiếu trường {name}");

    static IEnumerable<object> Items(object o, string name) => ((System.Collections.IEnumerable)P(o, name)).Cast<object>();

    static object D(ActionResult<AppResponse<object>> r) => Data(r);

    async Task<(Guid Store, Guid Tra, Guid Banh)> SeedAsync()
    {
        var store = await Fx.NewStoreAsync();
        var tra = await Fx.AddProductAsync(store, "Trà sữa", PosProductType.Goods, 100, 10000, 25000);
        var banh = await Fx.AddProductAsync(store, "Bánh", PosProductType.Goods, 100, 6000, 15000);
        var customer = new PosCustomer
        {
            Id = Guid.NewGuid(), StoreId = store, CustomerCode = "KH" + Guid.NewGuid().ToString("N")[..6],
            Name = "Chị Hoa", IsActive = true,
        };
        await using (var db = Fx.NewDb())
        {
            db.PosCustomers.Add(customer);
            await db.SaveChangesAsync();
        }

        var s1 = await SellAsync(store, 5000, 0, (tra.Id, 2, 25000, null), (banh.Id, 2, 15000, null));
        Assert.Null(Error(await ReturnAsync(store, s1.Id, (banh.Id, 1))));

        PosSalesController.SaleOrderDto s2;
        await using (var db = Fx.NewDb())
        {
            s2 = Data(await Sales(db, store).CreateSale(new PosSalesController.CreateSaleDto(
                [new PosSalesController.SaleLineDto(tra.Id, 4, null, 25000, null, DiscountAmount: 10000)],
                0, 50000, "Chuyển khoản", null, customer.Id, null)));
        }
        await using (var db = Fx.NewDb())
        {
            var ctl = PosPgFixture.As(new PosCustomersController(db), store);
            var pay = await ctl.AddPayment(customer.Id,
                new PosCustomersController.CreateCustomerPaymentDto(30000, "Tiền mặt", null, null, s2.Id));
            Assert.IsType<OkObjectResult>(pay.Result);
        }
        return (store, tra.Id, banh.Id);
    }

    static (DateTime, DateTime) Today()
    {
        var d = DateTime.UtcNow.AddHours(7).Date;
        return (d, d);
    }

    [Fact]
    public async Task Tien_mat_ket_gom_thu_no_va_tru_hoan_tra()
    {
        if (NoDb) return;
        var (store, _, _) = await SeedAsync();
        var (from, to) = Today();
        await using var db = Fx.NewDb();
        var e = D(await Reports(db, store).GetEndOfDay(from, to, null, null));
        Assert.Equal(30000m, N(e, "debtCollected"));
        Assert.Equal(14063m, N(e, "refundPaid"));
        // Trước đây = 75.000 (bỏ sót thu nợ và hoàn tiền).
        Assert.Equal(90937m, N(e, "drawerCash"));
        Assert.Equal(125000m + 30000m - 14063m, N(e, "fundInToday"));
    }

    [Fact]
    public async Task Da_thu_bang_tong_theo_phuong_thuc()
    {
        if (NoDb) return;
        var (store, _, _) = await SeedAsync();
        var (from, to) = Today();
        await using var db = Fx.NewDb();
        var s = D(await Reports(db, store).GetSalesSummary(from, to));
        var byPay = Items(s, "byPayment").ToList();
        Assert.Equal(125000m, byPay.Sum(x => N(x, "total")));
        // Trước đây = PaidAmount (60.937 + 80.000 gồm cả tiền trả nợ) → lệch biểu đồ PTTT.
        Assert.Equal(125000m, N(s, "totalPaid"));
    }

    [Fact]
    public async Task Giam_gia_gom_ca_giam_dong_o_moi_bao_cao()
    {
        if (NoDb) return;
        var (store, _, _) = await SeedAsync();
        var (from, to) = Today();
        await using var db = Fx.NewDb();
        Assert.Equal(15000m, N(D(await Reports(db, store).GetSalesSummary(from, to)), "totalDiscount"));
        Assert.Equal(15000m, N(D(await Reports(db, store).GetPnlSummary(from, to)), "discount"));
        Assert.Equal(15000m, N(P(D(await Reports(db, store).GetBusinessAnalysis(from, to)), "current"), "discount"));
    }

    [Fact]
    public async Task Doanh_thu_theo_hang_khop_tong_don_khong_so_le()
    {
        if (NoDb) return;
        var (store, tra, banh) = await SeedAsync();
        var (from, to) = Today();
        await using var db = Fx.NewDb();
        var g = D(await Reports(db, store).GetGoodsSummary(from, to));
        var top = Items(g, "topByRevenue").ToList();
        Assert.Equal(150937m, top.Sum(x => N(x, "revenue")));
        Assert.All(top, x => Assert.Equal(decimal.Truncate(N(x, "revenue")), N(x, "revenue")));
        var traRow = top.First(x => (Guid)P(x, "productId") == tra);
        Assert.Equal(10000m, N(traRow, "lineDiscount"));
        Assert.Equal(2m, N(traRow, "orderCount"));
        Assert.False(string.IsNullOrEmpty((string)P(traRow, "productCode")));

        var profit = D(await Reports(db, store).GetProfitByProduct(from, to));
        Assert.Equal(150937m, N(profit, "totalRevenue"));
        var banhRow = Items(profit, "items").First(x => (Guid)P(x, "productId") == banh);
        Assert.Equal(1m, N(banhRow, "orderCount"));
    }
}

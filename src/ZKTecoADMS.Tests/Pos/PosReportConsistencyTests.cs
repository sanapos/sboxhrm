using Microsoft.AspNetCore.Mvc;
using Xunit;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Tests.Pos;

/// <summary>
/// Mọi báo cáo bán hàng ra cùng một con số trên cùng dữ liệu (tính tay):
/// Đơn A: 3 Nước × 10.000 + 1 Bún (dịch vụ) 70.000, giảm giá đơn 10.000 → 90.000; khách trả 1 Nước (hoàn 9.000) → 81.000.
/// Đơn B: 2 Combo (Nước + Bánh) × 20.000 = 40.000.
/// Doanh thu thuần 121.000 · Giá vốn: Nước 2×4.000 + Bún 28.000 + Combo 2×(4.000+6.000) = 56.000 · Lãi gộp 65.000.
/// </summary>
[Collection("pos-pg")]
public class PosReportConsistencyTests(PosPgFixture fx) : PosFlowTestBase(fx)
{
    static decimal N(object o, string name) =>
        Convert.ToDecimal(o.GetType().GetProperty(name)?.GetValue(o)
                          ?? throw new Xunit.Sdk.XunitException($"Thiếu trường {name}"));

    static object P(object o, string name) =>
        o.GetType().GetProperty(name)?.GetValue(o) ?? throw new Xunit.Sdk.XunitException($"Thiếu trường {name}");

    static IEnumerable<object> Items(object o, string name) => ((System.Collections.IEnumerable)P(o, name)).Cast<object>();

    static object D(ActionResult<AppResponse<object>> r) => Data(r);

    async Task<(Guid Store, Guid Nuoc, Guid Bun, Guid Combo)> SeedAsync()
    {
        var store = await Fx.NewStoreAsync();
        var nuoc = await Fx.AddProductAsync(store, "Nước", PosProductType.Goods, 100, 4000, 10000);
        var banh = await Fx.AddProductAsync(store, "Bánh", PosProductType.Goods, 100, 6000, 15000);
        var bun = await Fx.AddProductAsync(store, "Bún chả", PosProductType.Service, 0, 28000, 70000);
        var combo = await Fx.AddProductAsync(store, "Combo", PosProductType.Combo, 0, 0, 20000);
        await AddComboLineAsync(store, combo.Id, nuoc.Id, 1);
        await AddComboLineAsync(store, combo.Id, banh.Id, 1);

        var a = await SellAsync(store, 10000, 0, (nuoc.Id, 3, 10000, null), (bun.Id, 1, 70000, null));
        await SellAsync(store, (combo.Id, 2, 20000, null));
        Assert.Null(Error(await ReturnAsync(store, a.Id, (nuoc.Id, 1))));
        return (store, nuoc.Id, bun.Id, combo.Id);
    }

    static (DateTime, DateTime) Range() => (DateTime.UtcNow.AddHours(7).Date.AddDays(-1), DateTime.UtcNow.AddHours(7).Date.AddDays(1));

    [Fact]
    public async Task Bao_cao_ban_hang_doanh_thu_gia_von_lai_dung()
    {
        if (NoDb) return;
        var (store, _, _, _) = await SeedAsync();
        var (from, to) = Range();
        await using var db = Fx.NewDb();
        var s = D(await Reports(db, store).GetSalesSummary(from, to));
        Assert.Equal(121000m, N(s, "totalRevenue"));
        Assert.Equal(56000m, N(s, "totalCogs"));
        Assert.Equal(65000m, N(s, "totalProfit"));
        Assert.Equal(9000m, N(s, "totalRefund"));
    }

    [Fact]
    public async Task Ket_qua_kinh_doanh_khong_tru_hoan_tra_hai_lan_khong_tru_vat()
    {
        if (NoDb) return;
        var (store, _, _, _) = await SeedAsync();
        var (from, to) = Range();
        await using var db = Fx.NewDb();
        var p = D(await Reports(db, store).GetPnlSummary(from, to));
        Assert.Equal(121000m, N(p, "revenue"));
        Assert.Equal(56000m, N(p, "cogs"));
        Assert.Equal(65000m, N(p, "grossProfit"));
        Assert.Equal(130000m, N(p, "grossSales"));
        Assert.Equal(9000m, N(p, "refunds"));
    }

    [Fact]
    public async Task Phan_tich_kinh_doanh_khop_bao_cao_ban_hang()
    {
        if (NoDb) return;
        var (store, _, _, _) = await SeedAsync();
        var (from, to) = Range();
        await using var db = Fx.NewDb();
        var a = D(await Reports(db, store).GetBusinessAnalysis(from, to));
        var cur = P(a, "current");
        Assert.Equal(121000m, N(cur, "revenue"));
        Assert.Equal(56000m, N(cur, "cogs"));
        Assert.Equal(65000m, N(cur, "profit"));
    }

    [Fact]
    public async Task Loi_nhuan_theo_hang_tru_hang_tra_chia_giam_gia_va_gia_von_khong_trung()
    {
        if (NoDb) return;
        var (store, nuoc, bun, combo) = await SeedAsync();
        var (from, to) = Range();
        await using var db = Fx.NewDb();
        var r = D(await Reports(db, store).GetProfitByProduct(from, to));
        Assert.Equal(121000m, N(r, "totalRevenue"));
        Assert.Equal(56000m, N(r, "totalCogs"));
        var items = Items(r, "items").ToDictionary(i => (Guid)P(i, "productId"));
        Assert.Equal(3, items.Count); // không có dòng thành phần combo «Topping» lỗ
        Assert.Equal(2m, N(items[nuoc], "qty"));
        Assert.Equal(18000m, N(items[nuoc], "revenue"));
        Assert.Equal(8000m, N(items[nuoc], "cogs"));
        Assert.Equal(63000m, N(items[bun], "revenue"));
        Assert.Equal(28000m, N(items[bun], "cogs"));
        Assert.Equal(40000m, N(items[combo], "revenue"));
        Assert.Equal(20000m, N(items[combo], "cogs"));
    }

    [Fact]
    public async Task Loi_nhuan_theo_kenh_va_nhom_khop_tong()
    {
        if (NoDb) return;
        var (store, _, _, _) = await SeedAsync();
        var (from, to) = Range();
        await using var db = Fx.NewDb();
        foreach (var dim in new[] { "channel", "staff", "category" })
        {
            var r = D(await Reports(db, store).GetProfitByDimension(from, to, dim));
            var rows = Items(r, "items").ToList();
            Assert.Equal(121000m, rows.Sum(x => N(x, "revenue")));
            Assert.Equal(56000m, rows.Sum(x => N(x, "cogs")));
        }
    }

    [Fact]
    public async Task Hang_ban_chay_tru_hang_tra()
    {
        if (NoDb) return;
        var (store, nuoc, bun, _) = await SeedAsync();
        var (from, to) = Range();
        await using var db = Fx.NewDb();
        var g = D(await Reports(db, store).GetGoodsSummary(from, to));
        var top = Items(g, "topByRevenue").ToList();
        Assert.Equal(121000m, top.Sum(x => N(x, "revenue")));
        Assert.Equal(bun, (Guid)P(top[0], "productId"));
        Assert.Equal(2m, N(top.First(x => (Guid)P(x, "productId") == nuoc), "qty"));
    }

    [Fact]
    public async Task Cuoi_ngay_khong_tru_hoan_tra_hai_lan()
    {
        if (NoDb) return;
        var (store, _, _, _) = await SeedAsync();
        var today = DateTime.UtcNow.AddHours(7).Date;
        await using var db = Fx.NewDb();
        var e = D(await Reports(db, store).GetEndOfDay(today, today, null, null));
        Assert.Equal(121000m, N(e, "netSales"));
        Assert.Equal(9000m, N(e, "refundTotal"));
        Assert.Equal(121000m, N(e, "totalAfterRefund"));
    }
}

using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Xunit;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Api.Controllers.Reports;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Tests.Pos;

/// <summary>
/// Báo cáo kỳ dài cộng trong CSDL (tập đơn là truy vấn con, đơn «thường» cộng thẳng bằng SQL) phải ra ĐÚNG từng con số
/// như cách cũ nạp hết về máy chủ (<see cref="PosReportMoneyV1"/>): đủ loại đơn khó — giảm giá đơn, trả hàng (sổ trả và
/// phiếu cũ chỉ có thẻ kho), hủy phiếu trả, combo, định lượng, topping, ĐVT quy đổi, SL lẻ, giảm giá dòng, VAT, đổi tên
/// hàng, giá vốn dịch vụ đơn cũ.
/// </summary>
[Collection("pos-pg")]
public class PosReportSqlAggregationTests(PosPgFixture fx) : PosFlowTestBase(fx)
{
    sealed record Seed(Guid Store, Guid Nuoc, Guid Banh, Guid Combo, Guid CaPhe, Guid TranChau, Guid Goi);

    async Task<PosSalesController.SaleOrderDto> SellLinesAsync(Guid store, decimal discount, decimal vat,
        params PosSalesController.SaleLineDto[] lines)
    {
        await using var db = Fx.NewDb();
        var dto = new PosSalesController.CreateSaleDto([.. lines], discount, 10_000_000, "Tiền mặt", null, null, null,
            VatAmount: vat);
        return Data(await Sales(db, store).CreateSale(dto));
    }

    static PosSalesController.SaleLineDto L(Guid product, decimal qty, decimal price, Guid? unit = null,
        decimal lineDiscount = 0, string? toppings = null) =>
        new(product, qty, unit, price, null, lineDiscount, ToppingsJson: toppings);

    async Task<Seed> SeedAsync()
    {
        var store = await Fx.NewStoreAsync();
        var nuoc = await Fx.AddProductAsync(store, "Nước", PosProductType.Goods, 1000, 4000, 10000);
        var banh = await Fx.AddProductAsync(store, "Bánh", PosProductType.Goods, 1000, 6000, 15000);
        var bun = await Fx.AddProductAsync(store, "Bún chả", PosProductType.Service, 0, 28000, 70000);
        var goi = await Fx.AddProductAsync(store, "Gội đầu", PosProductType.Service, 0, 20000, 50000);
        var combo = await Fx.AddProductAsync(store, "Combo", PosProductType.Combo, 0, 0, 20000);
        await AddComboLineAsync(store, combo.Id, nuoc.Id, 1);
        await AddComboLineAsync(store, combo.Id, banh.Id, 1);
        var sua = await Fx.AddProductAsync(store, "Sữa", PosProductType.Material, 1000, 100000, 0);
        var caphe = await Fx.AddProductAsync(store, "Cà phê", PosProductType.Goods, 0, 0, 25000);
        await AddRecipeLineAsync(store, caphe.Id, sua.Id, 0.05m);
        var tranchau = await Fx.AddProductAsync(store, "Trân châu", PosProductType.Topping, 1000, 1000, 5000,
            p => p.IsTopping = true);
        var gao = await Fx.AddProductAsync(store, "Gạo", PosProductType.Goods, 1000, 20000, 33333,
            p => p.AllowDecimalQty = true);
        var thung = await AddUnitAsync(store, nuoc.Id, "Thùng", 24);
        var toppings = $$"""[{"id":"{{tranchau.Id}}","name":"Trân châu","price":5000,"qty":1}]""";

        // Giảm giá đơn + trả 1 phần.
        var a = await SellLinesAsync(store, 10000, 0, L(nuoc.Id, 3, 10000), L(bun.Id, 1, 70000));
        Assert.Null(Error(await ReturnAsync(store, a.Id, (nuoc.Id, 1))));
        // Đơn thường: combo, hàng thường, ĐVT, định lượng, giảm giá dòng, VAT.
        await SellLinesAsync(store, 0, 0, L(combo.Id, 2, 20000));
        await SellLinesAsync(store, 0, 0, L(nuoc.Id, 2, 10000), L(banh.Id, 1, 15000));
        await SellLinesAsync(store, 0, 0, L(nuoc.Id, 1, 240000, thung));
        await SellLinesAsync(store, 0, 0, L(caphe.Id, 1, 25000));
        await SellLinesAsync(store, 0, 0, L(nuoc.Id, 2, 10000, lineDiscount: 1000));
        await SellLinesAsync(store, 0, 8000, L(banh.Id, 2, 15000), L(caphe.Id, 1, 25000));
        // Topping, SL lẻ (tiền dòng lẻ), voucher-like giảm giá đơn lớn.
        await SellLinesAsync(store, 0, 0, L(caphe.Id, 2, 25000, toppings: toppings));
        await SellLinesAsync(store, 0, 0, L(gao.Id, 1.5m, 33333));
        await SellLinesAsync(store, 7777, 0, L(nuoc.Id, 1, 10000), L(banh.Id, 3, 15000), L(caphe.Id, 1, 25000));
        // Trả hết combo; trả rồi hủy phiếu trả.
        var j = await SellLinesAsync(store, 0, 0, L(combo.Id, 1, 20000));
        Assert.Null(Error(await ReturnAsync(store, j.Id, (combo.Id, 1))));
        var k = await SellLinesAsync(store, 0, 0, L(banh.Id, 2, 15000));
        Assert.Null(Error(await ReturnAsync(store, k.Id, (banh.Id, 1))));
        await using (var db = Fx.NewDb())
        {
            var no = (await db.PosSaleReturnLines.FirstAsync(r => r.SaleOrderId == k.Id)).ReturnNo;
            Data(await Sales(db, store).CancelReturn(k.Id, new PosSalesController.CancelSaleReturnDto(no)));
        }
        // Phiếu trả cũ (trước sổ trả hàng): chỉ còn thẻ kho — hàng thường và combo.
        var n = await SellLinesAsync(store, 0, 0, L(nuoc.Id, 2, 10000), L(banh.Id, 1, 15000));
        Assert.Null(Error(await ReturnAsync(store, n.Id, (nuoc.Id, 1))));
        var o = await SellLinesAsync(store, 0, 0, L(combo.Id, 2, 20000));
        Assert.Null(Error(await ReturnAsync(store, o.Id, (combo.Id, 1))));
        // Dịch vụ đơn cũ chưa ghi giá vốn lúc bán → ước giá vốn hiện tại × SL.
        var g = await SellLinesAsync(store, 0, 0, L(goi.Id, 2, 50000), L(nuoc.Id, 1, 10000));
        // Total lệch tổng tiền dòng 1đ (làm tròn dồn vào món lớn nhất) và lệch xa (giữ nguyên tiền dòng).
        var off1 = await SellLinesAsync(store, 0, 0, L(nuoc.Id, 1, 10000), L(banh.Id, 1, 15000));
        var offFar = await SellLinesAsync(store, 0, 0, L(nuoc.Id, 3, 10000), L(caphe.Id, 1, 25000));
        await using (var db = Fx.NewDb())
        {
            await db.PosSaleOrders.Where(x => x.Id == off1.Id).ExecuteUpdateAsync(u => u.SetProperty(x => x.Total, x => x.Total - 1));
            await db.PosSaleOrders.Where(x => x.Id == offFar.Id).ExecuteUpdateAsync(u => u.SetProperty(x => x.Total, x => x.Total + 5000));
            await db.PosSaleReturnLines.Where(r => r.SaleOrderId == n.Id || r.SaleOrderId == o.Id).ExecuteDeleteAsync();
            await db.PosStockTransactions.Where(t => t.SaleOrderId == g.Id && t.Note == PosSaleStockHelper.ServiceCostNote)
                .ExecuteDeleteAsync();
            // Đổi tên hàng giữa kỳ: dòng cũ giữ tên cũ.
            await db.PosProducts.Where(p => p.Id == banh.Id).ExecuteUpdateAsync(s => s.SetProperty(p => p.Name, "Bánh mới"));
        }
        await SellLinesAsync(store, 0, 0, L(banh.Id, 1, 15000));
        return new Seed(store, nuoc.Id, banh.Id, combo.Id, caphe.Id, tranchau.Id, goi.Id);
    }

    static IQueryable<Guid> Scope(ZKTecoDbContext db, Guid store) =>
        db.PosSaleOrders.Where(o => o.StoreId == store && o.Status == PosSaleOrderStatus.Completed).Select(o => o.Id);

    static void SameMap<TK, TV>(IReadOnlyDictionary<TK, TV> expected, IReadOnlyDictionary<TK, TV> actual) where TK : notnull
    {
        Assert.Equal(expected.Keys.OrderBy(k => k).ToList(), actual.Keys.OrderBy(k => k).ToList());
        foreach (var (k, v) in expected) Assert.Equal(v, actual[k]);
    }

    [Fact]
    public async Task Ban_theo_hang_cong_trong_csdl_khop_cach_cu()
    {
        if (NoDb) return;
        var s = await SeedAsync();
        await using var db = Fx.NewDb();
        var ids = await Scope(db, s.Store).ToListAsync();

        var old = PosReportLineExpand.Aggregate(await PosReportMoneyV1.NetLinesAsync(db, s.Store, ids));
        var now = await PosReportMoney.ProductSalesAsync(db, s.Store, Scope(db, s.Store));

        Assert.Equal(old.Count, now.Count);
        Assert.Equal(old.Select(x => x.Revenue), now.Select(x => x.Revenue));
        var byId = now.ToDictionary(x => x.ProductId);
        foreach (var e in old)
        {
            var a = byId[e.ProductId];
            Assert.Equal(e.Qty, a.Qty);
            Assert.Equal(e.Revenue, a.Revenue);
            Assert.Equal(e.LineDiscount, a.LineDiscount);
            Assert.Equal(e.LastSoldAt, a.LastSoldAt);
            Assert.Equal(e.OrderCount, a.OrderCount);
            Assert.Equal(e.ProductName, a.ProductName);
        }
        // Có cả hai đường: đơn thường (CSDL) và đơn phức tạp (máy chủ); hàng đổi tên lấy tên trên dòng bán sớm nhất.
        Assert.Equal("Bánh", byId[s.Banh].ProductName);
        Assert.True(byId.ContainsKey(s.TranChau));
    }

    [Fact]
    public async Task Gia_von_theo_don_va_theo_hang_khop_cach_cu()
    {
        if (NoDb) return;
        var s = await SeedAsync();
        await using var db = Fx.NewDb();
        var ids = await Scope(db, s.Store).ToListAsync();

        var oldByOrder = await PosReportMoneyV1.CogsByOrderAsync(db, s.Store, ids);
        SameMap(oldByOrder, await PosReportMoney.CogsByOrderAsync(db, s.Store, Scope(db, s.Store)));
        SameMap(oldByOrder, await PosReportMoney.CogsByOrderAsync(db, s.Store, ids));
        Assert.Equal(oldByOrder.Values.Sum(), await PosReportMoney.CogsTotalAsync(db, s.Store, Scope(db, s.Store)));

        var oldReturned = await LedgerV1.ReturnedByOrderAsync(db, s.Store, ids);
        SameMap(oldReturned, await PosSaleReturnLedger.ReturnedByOrderAsync(db, s.Store, Scope(db, s.Store)));
        Assert.Equal(oldByOrder.Values.Sum() + oldReturned.Values.Sum(x => x.Cost),
            await PosReportMoney.SaleCogsTotalAsync(db, s.Store, Scope(db, s.Store)));
        SameMap(await LedgerV1.ReturnedQtyByLineAsync(db, s.Store, ids),
            await PosSaleReturnLedger.ReturnedQtyByLineAsync(db, s.Store, Scope(db, s.Store)));

        var oldByProduct = await PosReportMoneyV1.CogsByProductAsync(db, s.Store, ids);
        SameMap(oldByProduct, await PosReportMoney.CogsByProductAsync(db, s.Store, Scope(db, s.Store)));
        SameMap(oldByProduct, await PosReportMoney.CogsByProductAsync(db, s.Store, ids));
        // Dữ liệu thật sự có giá vốn combo / định lượng quy về món bán và giá vốn dịch vụ ước tính.
        Assert.True(oldByProduct[s.Combo] > 0);
        Assert.True(oldByProduct[s.CaPhe] > 0);
        Assert.Equal(40000m, oldByProduct[s.Goi]);

        var from = DateTime.UtcNow.AddDays(-1);
        var to = DateTime.UtcNow.AddDays(1);
        Assert.Equal(await LedgerV1.SumRefundsByReturnDateAsync(db, s.Store, from, to, ids),
            await PosSaleReturnLedger.SumRefundsByReturnDateAsync(db, s.Store, from, to, Scope(db, s.Store)));
        Assert.Equal(await LedgerV1.SumRefundsByReturnDateAsync(db, s.Store, from, to),
            await PosSaleReturnLedger.SumRefundsByReturnDateAsync(db, s.Store, from, to));
    }

    [Fact]
    public async Task Mot_phan_don_khop_cach_cu()
    {
        if (NoDb) return;
        var s = await SeedAsync();
        await using var db = Fx.NewDb();
        // Tập con: mỗi đơn thứ hai (truy vấn và danh sách) — không lẫn đơn ngoài tập.
        var some = (await Scope(db, s.Store).OrderBy(x => x).ToListAsync()).Where((_, i) => i % 2 == 0).ToList();
        var scope = db.PosSaleOrders.Where(o => some.Contains(o.Id)).Select(o => o.Id);

        var old = PosReportLineExpand.Aggregate(await PosReportMoneyV1.NetLinesAsync(db, s.Store, some))
            .ToDictionary(x => x.ProductId);
        var now = (await PosReportMoney.ProductSalesAsync(db, s.Store, scope)).ToDictionary(x => x.ProductId);
        Assert.Equal(old.Keys.OrderBy(k => k), now.Keys.OrderBy(k => k));
        foreach (var (id, e) in old)
            Assert.Equal((e.Qty, e.Revenue, e.LineDiscount, e.OrderCount), (now[id].Qty, now[id].Revenue, now[id].LineDiscount, now[id].OrderCount));
        SameMap(await PosReportMoneyV1.CogsByProductAsync(db, s.Store, some),
            await PosReportMoney.CogsByProductAsync(db, s.Store, scope));
        SameMap(await PosReportMoneyV1.CogsByOrderAsync(db, s.Store, some),
            await PosReportMoney.CogsByOrderAsync(db, s.Store, scope));
    }

    static decimal N(object o, string name) => Convert.ToDecimal(o.GetType().GetProperty(name)!.GetValue(o));
    static object P(object o, string name) => o.GetType().GetProperty(name)!.GetValue(o)!;
    static IEnumerable<object> Items(object o, string name) => ((System.Collections.IEnumerable)P(o, name)).Cast<object>();
    static object D(ActionResult<AppResponse<object>> r) => Data(r);

    [Fact]
    public async Task Bao_cao_ky_dai_khop_cach_cu()
    {
        if (NoDb) return;
        var s = await SeedAsync();
        var from = DateTime.UtcNow.AddHours(7).Date.AddDays(-1);
        var to = DateTime.UtcNow.AddHours(7).Date.AddDays(1);
        await using var db = Fx.NewDb();
        var ids = await db.PosSaleOrders
            .Where(o => o.StoreId == s.Store && o.IsActive && o.Status == PosSaleOrderStatus.Completed)
            .Select(o => o.Id).ToListAsync();
        var orders = await db.PosSaleOrders.Where(o => ids.Contains(o.Id)).ToListAsync();
        var oldAgg = PosReportLineExpand.Aggregate(await PosReportMoneyV1.NetLinesAsync(db, s.Store, ids));
        var oldCogs = (await PosReportMoneyV1.CogsByOrderAsync(db, s.Store, ids)).Values.Sum();
        var oldCogsByProduct = await PosReportMoneyV1.CogsByProductAsync(db, s.Store, ids);
        var oldReturned = await LedgerV1.ReturnedByOrderAsync(db, s.Store, ids);
        // Mọi phiếu trả đều trong hôm nay.
        var refund = await LedgerV1.SumRefundsByReturnDateAsync(db, s.Store, DateTime.UtcNow.AddDays(-1), DateTime.UtcNow.AddDays(1));
        var lineDiscount = await db.PosSaleOrderLines.Where(l => ids.Contains(l.SaleOrderId)).SumAsync(l => l.DiscountAmount);

        var sales = D(await Reports(db, s.Store).GetSalesSummary(from, to));
        Assert.Equal(orders.Sum(o => o.Total), N(sales, "totalRevenue"));
        Assert.Equal(orders.Sum(o => o.VatAmount), N(sales, "totalVat"));
        Assert.Equal(orders.Count, N(sales, "orderCount"));
        Assert.Equal(orders.Sum(o => o.Discount + o.VoucherDiscount + o.PointsDiscount) + lineDiscount, N(sales, "totalDiscount"));
        Assert.Equal(oldCogs, N(sales, "totalCogs"));
        Assert.Equal(refund, N(sales, "totalRefund"));
        var top = Items(sales, "topProducts").ToList();
        // Cùng doanh thu thì thứ tự có thể khác (cách cũ theo thứ tự dòng CSDL trả về) — so theo tập.
        Assert.Equal(oldAgg.Take(20).Select(x => x.Revenue), top.Select(x => N(x, "revenue")));
        Assert.Equal(oldAgg.Take(20).Select(x => (x.ProductId, x.Qty, x.Revenue)).OrderBy(x => x.ProductId),
            top.Select(x => ((Guid)P(x, "productId"), N(x, "qty"), N(x, "revenue"))).OrderBy(x => x.Item1));

        var analysis = D(await Reports(db, s.Store).GetBusinessAnalysis(from, to));
        var cur = P(analysis, "current");
        Assert.Equal(oldCogs, N(cur, "cogs"));
        Assert.Equal(orders.Sum(o => o.Total), N(cur, "revenue"));
        Assert.Equal(orders.Sum(o => o.Discount + o.VoucherDiscount + o.PointsDiscount) + lineDiscount, N(cur, "discount"));
        Assert.Equal(oldAgg.Sum(x => x.Revenue), Items(analysis, "topCategories").Sum(x => N(x, "revenue")));

        var goods = D(await Reports(db, s.Store).GetGoodsSummary(from, to, limit: 1000));
        var goodsRows = Items(goods, "topByRevenue").Select(x => ((Guid)P(x, "productId"), N(x, "qty"), N(x, "revenue"),
            N(x, "lineDiscount"), N(x, "orderCount"))).ToList();
        Assert.True(goodsRows.Count >= 5);
        Assert.Equal(oldAgg.Where(x => goodsRows.Any(r => r.Item1 == x.ProductId))
                .Select(x => (x.ProductId, x.Qty, x.Revenue, x.LineDiscount, (decimal)x.OrderCount)).OrderBy(x => x.ProductId),
            goodsRows.OrderBy(x => x.Item1));

        var profit = D(await Reports(db, s.Store).GetProfitByProduct(from, to, limit: 1000));
        foreach (var it in Items(profit, "items"))
        {
            var pid = (Guid)P(it, "productId");
            Assert.Equal(oldCogsByProduct.GetValueOrDefault(pid), N(it, "cogs"));
            Assert.Equal(oldAgg.FirstOrDefault(x => x.ProductId == pid)?.Revenue ?? 0, N(it, "revenue"));
        }

        var pnl = D(await Reports(db, s.Store).GetPnlSummary(from, to));
        Assert.Equal(oldCogs, N(pnl, "cogs"));
        Assert.Equal(oldCogs + oldReturned.Values.Sum(x => x.Cost), N(pnl, "saleCost"));
        Assert.Equal(oldReturned.Values.Sum(x => x.Refund), N(pnl, "refunds"));

        var dim = D(await Reports(db, s.Store).GetProfitByDimension(from, to, "category"));
        Assert.Equal(oldCogs, N(dim, "totalCogs"));
        Assert.Equal(oldAgg.Sum(x => x.Revenue), Items(dim, "items").Sum(x => N(x, "revenue")));
    }
}

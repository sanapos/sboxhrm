using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Xunit;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Tests.Pos;

/// <summary>Nhập hàng (giá vốn theo giá mua thực), xuất hủy / nội bộ, kiểm kê và cách chúng vào báo cáo.</summary>
[Collection("pos-pg")]
public class PosInventoryFlowTests(PosPgFixture fx) : PosFlowTestBase(fx)
{
    static decimal N(object o, string name) => Convert.ToDecimal(o.GetType().GetProperty(name)!.GetValue(o));
    static object P(object o, string name) => o.GetType().GetProperty(name)!.GetValue(o)!;
    static object D(ActionResult<AppResponse<object>> r) => Data(r);

    PosPurchaseReceiptsController Receipts(ZKTecoDbContext db, Guid store) =>
        PosPgFixture.As(new PosPurchaseReceiptsController(db, null!), store);

    async Task<Guid> ReceiveAsync(Guid store, Guid productId, decimal qty, decimal price, decimal lineDiscount = 0, decimal receiptDiscount = 0)
    {
        await using var db = Fx.NewDb();
        var dto = new PosPurchaseReceiptsController.SaveReceiptDto(
            null, null, null, null, receiptDiscount, false, receiptDiscount, 0, null, null, true, null, "Tiền mặt",
            [new PosPurchaseReceiptsController.ReceiptLineInput(productId, null, qty, price, lineDiscount, 0, false, true, null, null)]);
        return Data(await Receipts(db, store).Create(dto)).Id;
    }

    async Task IssueAsync(Guid store, string kind, Guid productId, decimal qty)
    {
        await using var db = Fx.NewDb();
        var ctl = PosPgFixture.As(new PosStockIssueKiotController(db), store);
        var issue = Data(await ctl.CreateIssue(kind));
        issue = Data(await ctl.AddLines(kind, issue.Id, [new PosStockIssueKiotController.AddIssueLineInput(productId, null)]));
        Data(await ctl.UpdateLines(kind, issue.Id, new PosStockIssueKiotController.UpdateIssueLinesDto(
            [new PosStockIssueKiotController.UpdateIssueLineDto(issue.Lines[0].Id, qty, null, null)])));
        Data(await ctl.CompleteIssue(kind, issue.Id));
    }

    async Task CountAsync(Guid store, Guid productId, decimal counted)
    {
        await using var db = Fx.NewDb();
        var ctl = PosPgFixture.As(new PosStockCountsController(db), store);
        var c = Data(await ctl.CreateCount(new PosStockCountsController.CreateStockCountDto("KK", null)));
        c = Data(await ctl.AddLines(c.Id, [new PosStockCountsController.AddCountLineInput(productId, null)]));
        Data(await ctl.UpdateLines(c.Id, new PosStockCountsController.UpdateCountLinesDto(
            [new PosStockCountsController.UpdateCountLineDto(c.Lines[0].Id, counted, true)])));
        Data(await ctl.CompleteCount(c.Id));
    }

    [Fact]
    public async Task Nhap_hang_gia_von_theo_gia_mua_thuc_va_huy_phieu_tra_ve()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var nuoc = await Fx.AddProductAsync(store, "Nước", PosProductType.Goods, 0, 0, 10000);

        // 10 × 5.000 − CK dòng 5.000 − CK phiếu 4.500 = 40.500 → 4.050 / chai
        await ReceiveAsync(store, nuoc.Id, 10, 5000, 5000, 4500);
        await using (var db = Fx.NewDb())
        {
            var p = await db.PosProducts.FirstAsync(x => x.Id == nuoc.Id);
            Assert.Equal(10, p.OnHandQty);
            Assert.Equal(4050m, p.CostPrice);
            var tx = await db.PosStockTransactions.SingleAsync(t => t.ProductId == nuoc.Id && t.TransactionType == PosStockTransactionType.StockIn);
            Assert.Equal(40500m, tx.LineAmount);
            Assert.Equal(4050m, tx.UnitCost);
        }

        var second = await ReceiveAsync(store, nuoc.Id, 10, 6000);
        await using (var db = Fx.NewDb())
        {
            var p = await db.PosProducts.FirstAsync(x => x.Id == nuoc.Id);
            Assert.Equal(5025m, p.CostPrice); // (40.500 + 60.000) / 20
            var tx = await db.PosStockTransactions.SingleAsync(t => t.StockReceiptId == second && t.TransactionType == PosStockTransactionType.StockIn);
            Assert.Equal(60000m, tx.LineAmount); // giá trị nhập = giá mua, không phải bình quân
            Data(await Receipts(db, store).Cancel(second));
        }
        await using (var db = Fx.NewDb())
            Assert.Equal(4050m, Math.Round((await db.PosProducts.FirstAsync(x => x.Id == nuoc.Id)).CostPrice, 2));
    }

    [Fact]
    public async Task Ket_qua_kinh_doanh_tinh_xuat_huy_xuat_noi_bo_va_kiem_ke_thieu()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var nuoc = await Fx.AddProductAsync(store, "Nước", PosProductType.Goods, 0, 0, 10000);
        await ReceiveAsync(store, nuoc.Id, 20, 4000);

        await IssueAsync(store, "damage", nuoc.Id, 2);        // 8.000
        await IssueAsync(store, "internal-use", nuoc.Id, 3);  // 12.000
        await CountAsync(store, nuoc.Id, 14);                 // tồn 15 → đếm 14: thiếu 1 = 4.000
        Assert.Equal(14, await OnHandAsync(nuoc.Id));

        var (from, to) = (DateTime.UtcNow.AddHours(7).Date.AddDays(-1), DateTime.UtcNow.AddHours(7).Date.AddDays(1));
        await using var db = Fx.NewDb();
        var p = D(await Reports(db, store).GetPnlSummary(from, to));
        Assert.Equal(8000m, N(p, "damageCost"));
        Assert.Equal(12000m, N(p, "internalUseCost"));
        Assert.Equal(4000m, N(p, "countLossCost"));
        Assert.Equal(-24000m, N(p, "netProfit"));
    }

    [Fact]
    public async Task Ton_kho_khong_dem_combo_va_dich_vu_la_het_hang_nguyen_lieu_khong_ton_chet()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var bot = await Fx.AddProductAsync(store, "Cà phê bột", PosProductType.Material, 1000, 200, 0);
        var ly = await Fx.AddProductAsync(store, "Cà phê sữa", PosProductType.Goods, 0, 0, 29000);
        await AddRecipeLineAsync(store, ly.Id, bot.Id, 25);
        await Fx.AddProductAsync(store, "Combo", PosProductType.Combo, 0, 0, 50000);
        await Fx.AddProductAsync(store, "Bún", PosProductType.Service, 0, 28000, 70000);
        await SellAsync(store, (ly.Id, 2, 29000, null));

        var (from, to) = (DateTime.UtcNow.AddHours(7).Date.AddDays(-1), DateTime.UtcNow.AddHours(7).Date.AddDays(1));
        await using var db = Fx.NewDb();
        var reports = Reports(db, store);
        var sum = D(await reports.GetStockSummary());
        // Chỉ «Cà phê sữa» (hàng hóa, tồn 0 vì bán theo định lượng) là hết hàng; combo / dịch vụ không tính.
        Assert.Equal(1m, N(sum, "outOfStock"));

        // NVL dùng qua định lượng (50 g) không bị xếp «tồn chết» (trước đây chỉ đếm dòng hóa đơn).
        var dead = D(await reports.GetStockHealth(from, to, "dead"));
        Assert.DoesNotContain(((System.Collections.IEnumerable)P(dead, "items")).Cast<object>(),
            x => (Guid)P(x, "Id") == bot.Id);
    }
}

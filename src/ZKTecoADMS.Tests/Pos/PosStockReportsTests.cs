using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Xunit;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Tests.Pos;

/// <summary>Báo cáo Tồn kho, Hàng sắp hết hạn, Sức khỏe kho, Nhập hàng: số liệu khớp nhau giữa KPI, bộ lọc và danh sách.</summary>
[Collection("pos-pg")]
public class PosStockReportsTests(PosPgFixture fx) : PosFlowTestBase(fx)
{
    static decimal N(object o, string name) => Convert.ToDecimal(o.GetType().GetProperty(name)!.GetValue(o));
    static object? P(object o, string name) => o.GetType().GetProperty(name)!.GetValue(o);
    static object D(ActionResult<AppResponse<object>> r) => Data(r);
    static List<object> Items(object data) => ((System.Collections.IEnumerable)P(data, "items")!).Cast<object>().ToList();
    static DateTime VnToday => DateTime.UtcNow.AddHours(7).Date;

    async Task AgeProductAsync(Guid productId, int days)
    {
        await using var db = Fx.NewDb();
        await db.PosProducts.Where(p => p.Id == productId)
            .ExecuteUpdateAsync(s => s.SetProperty(p => p.CreatedAt, DateTime.UtcNow.AddDays(-days)));
    }

    [Fact]
    public async Task Ton_kho_KPI_khop_bo_loc_moi_hang_dung_mot_tinh_trang()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        await Fx.AddProductAsync(store, "Hết", PosProductType.Goods, 0, 1000, 2000, p => p.MinStockQty = 5);
        await Fx.AddProductAsync(store, "Thiếu", PosProductType.Goods, 2, 1000, 2000, p => p.MinStockQty = 5);
        await Fx.AddProductAsync(store, "Dư", PosProductType.Goods, 50, 1000, 2000, p => p.MaxStockQty = 20);
        await Fx.AddProductAsync(store, "Đủ", PosProductType.Goods, 10, 1000, 2000, p => p.MinStockQty = 5);

        await using var db = Fx.NewDb();
        var r = Reports(db, store);
        var sum = D(await r.GetStockSummary());
        Assert.Equal(4m, N(sum, "totalSkus"));
        Assert.Equal(1m, N(sum, "outOfStock"));
        Assert.Equal(1m, N(sum, "belowMin"));
        Assert.Equal(1m, N(sum, "aboveMax"));
        Assert.Equal(1m, N(sum, "okCount"));
        Assert.Equal(62000m, N(sum, "inventoryValue"));

        // Trước đây lọc «Dưới tối thiểu» ra cả hàng hết (2 dòng) trong khi ô KPI ghi 1.
        foreach (var (f, name) in new[] { ("BelowMin", "Thiếu"), ("OutOfStock", "Hết"), ("AboveMax", "Dư") })
        {
            var list = D(await r.GetStockProducts(null, f));
            Assert.Equal(1m, N(list, "total"));
            Assert.Equal(name, (string)P(Items(list).Single(), "Name")!);
        }
        var byValue = Items(D(await r.GetStockProducts(null, null, sort: "value")));
        Assert.Equal("Dư", (string)P(byValue[0], "Name")!);
    }

    [Fact]
    public async Task Han_dung_mac_dinh_can_xu_ly_nguong_0_thanh_30_lo_khong_hsd_rieng()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        // Ngưỡng cảnh báo 0 (dữ liệu cũ) → 30 ngày: bộ lọc, KPI và nhãn cùng coi lô còn 10 ngày là «sắp hết».
        var sua = await Fx.AddProductAsync(store, "Sữa", PosProductType.Goods, 10, 1000, 2000, p => p.ExpiryWarningDays = 0);
        var gao = await Fx.AddProductAsync(store, "Gạo", PosProductType.Goods, 10, 1000, 2000);
        var xoa = await Fx.AddProductAsync(store, "Đã xóa", PosProductType.Goods, 10, 1000, 2000, p => p.Deleted = DateTime.UtcNow);
        var today = DateTime.SpecifyKind(VnToday, DateTimeKind.Utc);
        await using (var db = Fx.NewDb())
        {
            PosStockLot Lot(Guid pid, DateTime? exp) => new()
            {
                Id = Guid.NewGuid(), StoreId = store, ProductId = pid, ExpiryDate = exp, QtyOnHand = 2, UnitCost = 1000,
                Status = PosStockLotStatus.Active, IsActive = true,
            };
            db.PosStockLots.AddRange(
                Lot(sua.Id, today.AddDays(10)),
                Lot(sua.Id, today.AddDays(-1)),
                Lot(gao.Id, today.AddDays(200)),
                Lot(gao.Id, null),
                Lot(xoa.Id, today.AddDays(-5)));
            await db.SaveChangesAsync();
        }

        await using var db2 = Fx.NewDb();
        var r = Reports(db2, store);
        var sum = D(await r.GetStockLotsSummary());
        Assert.Equal(4m, N(sum, "activeLotCount")); // lô của hàng đã xóa không tính
        Assert.Equal(1m, N(sum, "expiringSoonLotCount"));
        Assert.Equal(1m, N(sum, "expiredLotCount"));
        Assert.Equal(1m, N(sum, "noExpiryLotCount"));

        var attention = Items(D(await r.GetStockLotsReport(null, "attention")));
        Assert.Equal(2, attention.Count);
        Assert.Equal("expired", (string)P(attention[0], "status")!);
        Assert.Equal("expiring", (string)P(attention[1], "status")!);
        Assert.Equal(10, (int)P(attention[1], "daysUntilExpiry")!);

        var expiring = Items(D(await r.GetStockLotsReport(null, "expiring")));
        Assert.Equal("expiring", (string)P(expiring.Single(), "status")!); // trước đây lọc ra lô mang nhãn «Còn hạn»
        Assert.Equal("noexpiry", (string)P(Items(D(await r.GetStockLotsReport(null, "noexpiry"))).Single(), "status")!);
        Assert.Equal(4m, N(D(await r.GetStockLotsReport(null, null)), "total"));
    }

    [Fact]
    public async Task Suc_khoe_kho_theo_toc_do_ban_hang_moi_nhap_khong_phai_chet_ton()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var chay = await Fx.AddProductAsync(store, "Bán chạy", PosProductType.Goods, 11, 1000, 2000);
        var cham = await Fx.AddProductAsync(store, "Bán chậm", PosProductType.Goods, 1000, 1000, 2000);
        var chet = await Fx.AddProductAsync(store, "Chết tồn", PosProductType.Goods, 5, 1000, 2000);
        var moi = await Fx.AddProductAsync(store, "Mới về", PosProductType.Goods, 5, 1000, 2000);
        await AgeProductAsync(chet.Id, 120);
        await AgeProductAsync(cham.Id, 120);
        await SellAsync(store, (chay.Id, 10, 2000, null), (cham.Id, 1, 2000, null));

        var from = VnToday.AddDays(-29);
        await using var db = Fx.NewDb();
        var r = Reports(db, store);
        var all = D(await r.GetStockHealth(from, VnToday, "all"));
        Assert.Equal(30m, N(all, "periodDays"));
        var rows = Items(D(await r.GetStockHealth(from, VnToday, "all")))
            .ToDictionary(x => (Guid)P(x, "Id")!, x => (string)P(x, "status")!);
        Assert.Equal("hot", rows[chay.Id]);   // còn 1, bán 10 / 30 ngày → đủ bán ~3 ngày
        Assert.Equal("slow", rows[cham.Id]);  // còn 999, bán 1 → đủ bán hàng nghìn ngày
        Assert.Equal("dead", rows[chet.Id]);
        Assert.False(rows.ContainsKey(moi.Id)); // mới tạo, chưa bán → «mới về», không nằm trong «cần xử lý»
        Assert.Equal(1m, N(all, "newCount"));
        var news = Items(D(await r.GetStockHealth(from, VnToday, "new")));
        Assert.Equal(moi.Id, (Guid)P(news.Single(), "Id")!);
        Assert.Equal(5000m, N(all, "deadValue"));
    }

    [Fact]
    public async Task Nhap_hang_tra_ncc_sau_chiet_khau_va_cong_no_tren_phieu()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var nuoc = await Fx.AddProductAsync(store, "Nước", PosProductType.Goods, 0, 0, 10000);
        await using (var db = Fx.NewDb())
        {
            var dto = new PosPurchaseReceiptsController.SaveReceiptDto(
                null, null, null, null, 0, false, 0, 40000, null, null, true, null, "Tiền mặt",
                [new PosPurchaseReceiptsController.ReceiptLineInput(nuoc.Id, null, 10, 10000, 0, 0, false, true, null, null)]);
            Data(await PosPgFixture.As(new PosPurchaseReceiptsController(db, null!), store).Create(dto));
            db.PosPurchaseReturns.Add(new PosPurchaseReturn
            {
                Id = Guid.NewGuid(), StoreId = store, ReturnNo = "THN1", TotalAmount = 30000, DiscountAmount = 5000,
                Status = PosPurchaseReturnStatus.Completed, ReturnDate = DateTime.UtcNow, IsActive = true,
            });
            await db.SaveChangesAsync();
        }

        await using var db2 = Fx.NewDb();
        var d = D(await Reports(db2, store).GetPurchasesSummary(VnToday.AddDays(-1), VnToday));
        Assert.Equal(100000m, N(d, "receiptAmount"));
        Assert.Equal(25000m, N(d, "returnAmount"));       // NCC phải hoàn = 30.000 − CK 5.000 (trước đây 30.000)
        Assert.Equal(75000m, N(d, "netAmount"));
        Assert.Equal(40000m, N(d, "paidOnReceipts"));
        Assert.Equal(60000m, N(d, "balanceDue"));
        var top = ((System.Collections.IEnumerable)P(d, "topProducts")!).Cast<object>().Single();
        Assert.Equal(10m, N(top, "qty"));
        Assert.Equal(100000m, N(top, "amount"));
    }
}

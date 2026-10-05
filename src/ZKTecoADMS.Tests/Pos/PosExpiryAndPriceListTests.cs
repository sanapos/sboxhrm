using Microsoft.EntityFrameworkCore;
using Xunit;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Tests.Pos;

/// <summary>Bán không lấy lô quá hạn, cảnh báo HSD theo từng hàng, sao chép bảng giá.</summary>
[Collection("pos-pg")]
public class PosExpiryAndPriceListTests(PosPgFixture fx) : PosFlowTestBase(fx)
{
    async Task<Guid> AddLotAsync(Guid store, Guid productId, decimal qty, DateTime? expiry)
    {
        await using var db = Fx.NewDb();
        var lot = new PosStockLot
        {
            Id = Guid.NewGuid(), StoreId = store, ProductId = productId, LotNo = "L" + Guid.NewGuid().ToString("N")[..4],
            ExpiryDate = expiry, QtyOnHand = qty, UnitCost = 1000, Status = PosStockLotStatus.Active, IsActive = true,
        };
        db.PosStockLots.Add(lot);
        await db.SaveChangesAsync();
        return lot.Id;
    }

    async Task<decimal> LotQtyAsync(Guid lotId)
    {
        await using var db = Fx.NewDb();
        return (await db.PosStockLots.FirstAsync(l => l.Id == lotId)).QtyOnHand;
    }

    [Fact]
    public async Task Ban_hang_bo_qua_lo_qua_han_va_bao_loi_ro_khi_chi_con_lo_het_han()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var sua = await Fx.AddProductAsync(store, "Sữa", PosProductType.Goods, 8, 1000, 5000, p => p.TrackExpiry = true);
        var today = PosStockLotHelper.ExpiryCutoffUtc();
        var expired = await AddLotAsync(store, sua.Id, 5, today.AddDays(-2));
        var valid = await AddLotAsync(store, sua.Id, 3, today.AddDays(20));

        await SellAsync(store, (sua.Id, 2, 5000, null));
        Assert.Equal(5, await LotQtyAsync(expired));   // trước đây FEFO lấy lô hết hạn trước
        Assert.Equal(1, await LotQtyAsync(valid));

        await using var db = Fx.NewDb();
        var total = 3 * 5000m;
        var res = await Sales(db, store).CreateSale(new PosSalesController.CreateSaleDto(
            [new PosSalesController.SaleLineDto(sua.Id, 3, null, 5000, null)], 0, total, "Tiền mặt", null, null, null));
        Assert.Contains("quá hạn", Error(res) ?? "");
        Assert.Equal(5, await LotQtyAsync(expired));
    }

    [Fact]
    public async Task Canh_bao_han_su_dung_theo_so_ngay_cua_tung_hang()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var a = await Fx.AddProductAsync(store, "Rau", PosProductType.Goods, 0, 0, 0, p => { p.TrackExpiry = true; p.ExpiryWarningDays = 3; });
        var b = await Fx.AddProductAsync(store, "Gạo", PosProductType.Goods, 0, 0, 0, p => { p.TrackExpiry = true; p.ExpiryWarningDays = 60; });
        var today = PosStockLotHelper.ExpiryCutoffUtc();
        await AddLotAsync(store, a.Id, 1, today.AddDays(10));  // rau còn 10 ngày, ngưỡng 3 → chưa cảnh báo
        await AddLotAsync(store, b.Id, 1, today.AddDays(10));  // gạo còn 10 ngày, ngưỡng 60 → sắp hết hạn
        await AddLotAsync(store, a.Id, 1, today.AddDays(-1));  // hết hạn

        await using var db = Fx.NewDb();
        var lots = await PosStockAlertHelper.ExpiryLotsAsync(db, store);
        Assert.Equal(2, lots.Count);
        Assert.Single(lots, l => l.Expired && l.ProductId == a.Id);
        Assert.Single(lots, l => !l.Expired && l.ProductId == b.Id);
    }

    [Fact]
    public async Task Sao_chep_bang_gia_dieu_chinh_phan_tram_va_lam_tron()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var thit = await Fx.AddProductAsync(store, "Thịt", PosProductType.Goods, 0, 0, 150000);
        await using var db = Fx.NewDb();
        var ctl = PosPgFixture.As(new PosPriceListsController(db), store);
        var src = Data(await ctl.Create(new PosPriceListsController.PriceListUpsertDto("Giá lẻ", false, true, 1, null, null)));
        Data(await ctl.UpsertItems(src.Id, new PosPriceListsController.PriceListItemBulkDto(
            [new PosPriceListsController.PriceListItemInput(thit.Id, null, null, 152300)])));

        var copy = Data(await ctl.Copy(src.Id, new PosPriceListsController.PriceListCopyDto("Giá sỉ", -10, 1000, null, null)));
        Assert.Equal("Giá sỉ", copy.Name);
        Assert.Equal(1, copy.ItemCount);
        Assert.False(copy.IsDefault);
        await using var db2 = Fx.NewDb();
        var item = await db2.PosPriceListItems.SingleAsync(i => i.PriceListId == copy.Id);
        Assert.Equal(137000m, item.Price); // 152.300 × 90% = 137.070 → tròn nghìn
    }
}

using Microsoft.EntityFrameworkCore;
using Xunit;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Tests.Pos;

/// <summary>Khuyến mãi: lưu cấu hình, danh sách đang hiệu lực (kèm hàng cận hạn), ghi trên hóa đơn và báo cáo hiệu quả.</summary>
[Collection("pos-pg")]
public class PosPromotionTests(PosPgFixture fx) : PosFlowTestBase(fx)
{
    static object P(object o, string name) => o.GetType().GetProperty(name)!.GetValue(o)!;

    PosPromotionsController Promos(ZKTecoADMS.Infrastructure.ZKTecoDbContext db, Guid store) =>
        PosPgFixture.As(new PosPromotionsController(db), store);

    [Fact]
    public async Task Tao_sua_kiem_tra_va_danh_sach_dang_hieu_luc()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        await using var db = Fx.NewDb();
        var ctl = Promos(db, store);

        Assert.NotNull(Error(await ctl.Create(new("", "time_discount", 0, false, null, null, 0, null, null, false, "{}", null))));
        Assert.NotNull(Error(await ctl.Create(new("X", "bogus", 0, false, null, null, 0, null, null, false, "{}", null))));
        Assert.NotNull(Error(await ctl.Create(new("X", "time_discount", 0, false, null, null, 0, null, null, false, "[1]", null))));

        var today = DateTime.UtcNow.AddHours(7).Date;
        var live = Data(await ctl.Create(new("Giờ vàng", "time_discount", 1, false, today, today.AddDays(3), 0,
            18 * 60, 21 * 60, false, "{\"percent\":30}", null)));
        Data(await ctl.Create(new("Hết hạn", "time_discount", 0, false, today.AddDays(-10), today.AddDays(-1), 0,
            null, null, false, "{\"percent\":10}", null)));
        var off = Data(await ctl.Create(new("Tắt", "bill_discount", 0, false, null, null, 0, null, null, false, "{}", null, IsActive: false)));

        var active = Data(await ctl.Active());
        Assert.Equal([live.Id], active.Select(a => a.Id).ToList());
        Assert.Equal(3, Data(await ctl.List()).Count);

        Data(await ctl.Update(off.Id, new("Bật lại", "bill_discount", 0, false, null, null, 0, null, null, false,
            "{\"minBill\":100000,\"billAmount\":10000}", null)));
        Assert.Equal(2, Data(await ctl.Active()).Count);
        Data(await ctl.Delete(off.Id));
        Assert.Single(Data(await ctl.Active()));
    }

    [Fact]
    public async Task Hang_can_han_server_tinh_san_theo_lo_con_han_gan_nhat()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var sua = await Fx.AddProductAsync(store, "Sữa", PosProductType.Goods, 5, 0, 20000);
        var gao = await Fx.AddProductAsync(store, "Gạo", PosProductType.Goods, 5, 0, 20000);
        var today = PosStockLotHelper.ExpiryCutoffUtc();
        await using (var db = Fx.NewDb())
        {
            db.PosStockLots.AddRange(
                new PosStockLot { Id = Guid.NewGuid(), StoreId = store, ProductId = sua.Id, ExpiryDate = today.AddDays(2), QtyOnHand = 2, Status = PosStockLotStatus.Active, IsActive = true },
                new PosStockLot { Id = Guid.NewGuid(), StoreId = store, ProductId = gao.Id, ExpiryDate = today.AddDays(30), QtyOnHand = 2, Status = PosStockLotStatus.Active, IsActive = true },
                // lô đã hết hạn không tính (không bán được)
                new PosStockLot { Id = Guid.NewGuid(), StoreId = store, ProductId = gao.Id, ExpiryDate = today.AddDays(-1), QtyOnHand = 2, Status = PosStockLotStatus.Active, IsActive = true });
            await db.SaveChangesAsync();
        }
        await using var db2 = Fx.NewDb();
        var ctl = Promos(db2, store);
        Data(await ctl.Create(new("Cận hạn", "near_expiry", 0, false, null, null, 0, null, null, false,
            "{\"percent\":50,\"nearExpiryDays\":3}", null)));
        var p = Assert.Single(Data(await ctl.Active()));
        Assert.Equal([sua.Id], p.ResolvedProductIds);
    }

    [Fact]
    public async Task Hoa_don_luu_khuyen_mai_va_bao_cao_hieu_qua()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var rau = await Fx.AddProductAsync(store, "Rau", PosProductType.Goods, 10, 5000, 10000);
        var promoId = Guid.NewGuid();
        var json = $"{{\"applied\":[{{\"id\":\"{promoId}\",\"name\":\"Giờ vàng\",\"amount\":6000}}],\"lines\":{{\"{rau.Id}||\":6000}},\"bill\":0}}";

        await using (var db = Fx.NewDb())
        {
            // 2 × 10.000 − KM 6.000 trên dòng = 14.000
            var dto = new PosSalesController.CreateSaleDto(
                [new PosSalesController.SaleLineDto(rau.Id, 2, null, 10000, null, DiscountAmount: 6000)],
                0, 14000, "Tiền mặt", null, null, null, PromotionsJson: json);
            var order = Data(await Sales(db, store).CreateSale(dto));
            Assert.Equal(json, order.PromotionsJson);
            Assert.Equal(14000m, order.Total);
        }
        await using (var db = Fx.NewDb())
        {
            var o = await db.PosSaleOrders.SingleAsync(x => x.StoreId == store);
            Assert.Equal(6000m, o.PromotionDiscount);
            var rep = Data(await Promos(db, store).Report(null, null));
            Assert.Equal(6000m, (decimal)P(rep, "totalDiscount"));
            var item = ((System.Collections.IEnumerable)P(rep, "items")).Cast<object>().Single();
            Assert.Equal("Giờ vàng", (string)P(item, "name"));
            Assert.Equal(1, (int)P(item, "orders"));
        }
        Assert.Equal((null, 0m), PosPromotionsController.Sanitize("không phải json"));
    }
}

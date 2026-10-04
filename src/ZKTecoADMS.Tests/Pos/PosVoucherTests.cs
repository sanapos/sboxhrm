using Microsoft.EntityFrameworkCore;
using Xunit;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Tests.Pos;

/// <summary>Voucher giới hạn lượt phải tính lượt cả khi bán cho khách lẻ.</summary>
[Collection("pos-pg")]
public class PosVoucherTests(PosPgFixture fx) : PosFlowTestBase(fx)
{
    [Fact]
    public async Task Khach_le_dung_voucher_1_luot_thi_lan_2_bi_tu_choi()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var nuoc = await Fx.AddProductAsync(store, "Nước", PosProductType.Goods, 50, 4000, 10000);
        Guid voucherId;
        await using (var db = Fx.NewDb())
        {
            var v = new PosVoucher
            {
                Id = Guid.NewGuid(), StoreId = store, Code = "MOT", DiscountType = PosVoucherDiscountType.Fixed,
                DiscountValue = 5000, MaxUses = 1, IsActive = true,
            };
            db.PosVouchers.Add(v);
            await db.SaveChangesAsync();
            voucherId = v.Id;
        }

        async Task<string?> SellWithVoucher()
        {
            await using var db = Fx.NewDb();
            var dto = new PosSalesController.CreateSaleDto(
                [new PosSalesController.SaleLineDto(nuoc.Id, 2, null, 10000, null)],
                0, 15000, "Tiền mặt", null, null, null, VoucherCode: "MOT");
            return Error(await Sales(db, store).CreateSale(dto));
        }

        Assert.Null(await SellWithVoucher());
        await using (var db = Fx.NewDb())
            Assert.Equal(1, (await db.PosVouchers.FirstAsync(v => v.Id == voucherId)).UsedCount);

        // Lượt thứ hai (vẫn khách lẻ) phải bị chặn — trước đây khách lẻ không bị đếm lượt.
        Assert.NotNull(await SellWithVoucher());
    }
}

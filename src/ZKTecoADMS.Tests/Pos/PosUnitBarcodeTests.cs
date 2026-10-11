using System.Text.Json;
using Xunit;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Tests.Pos;

/// <summary>Mã vạch riêng của đơn vị bán (thùng / lốc): gán, chặn trùng, quét ở bán hàng ra đúng đơn vị.</summary>
[Collection("pos-pg")]
public class PosUnitBarcodeTests(PosPgFixture fx) : PosFlowTestBase(fx)
{
    async Task<(Guid store, Guid productId)> SetupAsync()
    {
        var store = await Fx.NewStoreAsync();
        await using var db = Fx.NewDb();
        var p = new PosProduct
        {
            Id = Guid.NewGuid(), StoreId = store, ProductCode = "BIA01", Barcode = "8934588012228",
            Name = "Bia Tiger lon", BaseUnitName = "Lon", BasePrice = 18000, IsDirectSale = true, IsActive = true,
        };
        db.PosProducts.Add(p);
        await db.SaveChangesAsync();
        return (store, p.Id);
    }

    PosProductUnitsController Units(ZKTecoADMS.Infrastructure.ZKTecoDbContext db, Guid store) =>
        PosPgFixture.As(new PosProductUnitsController(db), store);

    [Fact]
    public async Task Gan_ma_vach_thung_va_chan_trung()
    {
        if (NoDb) return;
        var (store, pid) = await SetupAsync();
        await using var db = Fx.NewDb();
        var ok = await Units(db, store).CreateUnit(pid,
            new PosProductUnitsController.UnitUpsertDto("Thùng", 24, 420000, true, " 8934588012235 "));
        Assert.Equal("8934588012235", Data(ok).Barcode);

        // Trùng mã thùng vừa gán.
        var dupUnit = await Units(db, store).CreateUnit(pid,
            new PosProductUnitsController.UnitUpsertDto("Lốc", 6, 105000, true, "8934588012235"));
        Assert.Contains("đã dùng cho đơn vị", Error(dupUnit));

        // Trùng mã vạch của chính lon (hàng hóa).
        var dupProduct = await Units(db, store).CreateUnit(pid,
            new PosProductUnitsController.UnitUpsertDto("Lốc", 6, 105000, true, "8934588012228"));
        Assert.Contains("đã dùng cho hàng", Error(dupProduct));

        // Sửa đơn vị giữ nguyên mã của chính nó → không báo trùng; bỏ trống → xóa mã.
        var unitId = Data(ok).Id;
        var same = await Units(db, store).UpdateUnit(pid, unitId,
            new PosProductUnitsController.UnitUpsertDto("Thùng", 24, 430000, true, "8934588012235"));
        Assert.Equal(430000, Data(same).BasePrice);
        // Luồng cũ không gửi mã (null) → giữ nguyên mã thùng.
        var kept = await Units(db, store).UpdateUnit(pid, unitId,
            new PosProductUnitsController.UnitUpsertDto("Thùng", 24, 430000, true));
        Assert.Equal("8934588012235", Data(kept).Barcode);
        var cleared = await Units(db, store).UpdateUnit(pid, unitId,
            new PosProductUnitsController.UnitUpsertDto("Thùng", 24, 430000, true, ""));
        Assert.Null(Data(cleared).Barcode);
    }

    [Fact]
    public async Task Quet_ma_thung_o_ban_hang_ra_dung_don_vi()
    {
        if (NoDb) return;
        var (store, pid) = await SetupAsync();
        await using var db = Fx.NewDb();
        var unit = Data(await Units(db, store).CreateUnit(pid,
            new PosProductUnitsController.UnitUpsertDto("Thùng", 24, 420000, true, "8934588012235")));

        var r = Data(await Sales(db, store).Lookup("8934588012235"));
        var json = JsonSerializer.SerializeToElement(r);
        Assert.Equal("unit", json.GetProperty("matchType").GetString());
        Assert.Equal(unit.Id, json.GetProperty("unit").GetProperty("UnitId").GetGuid());
        Assert.Equal(24, json.GetProperty("unit").GetProperty("ConversionRate").GetDecimal());
        Assert.Equal(pid, json.GetProperty("product").GetProperty("Id").GetGuid());

        // Mã lon vẫn ra hàng (đơn vị cơ bản).
        var lon = JsonSerializer.SerializeToElement(Data(await Sales(db, store).Lookup("8934588012228")));
        Assert.Equal("product", lon.GetProperty("matchType").GetString());
    }
}

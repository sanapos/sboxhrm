using Xunit;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Tests.Pos;

/// <summary>Kiểm kho bằng máy quét: lô mã barcode / mã thùng / thẻ RFID cộng thẳng vào số đếm.</summary>
[Collection("pos-pg")]
public class PosStockCountScanTests(PosPgFixture fx) : PosFlowTestBase(fx)
{
    [Fact]
    public void Sgtin96_giai_ra_gtin_theo_vi_du_gs1()
    {
        // GS1 EPC Tag Data Standard: urn:epc:id:sgtin:0614141.812345.6789 (filter 3, partition 5).
        Assert.True(PosScanCodes.TryGtinFromSgtin96("3074257BF7194E4000001A85", out var gtin));
        Assert.Equal("80614141123458", gtin);
        Assert.False(PosScanCodes.TryGtinFromSgtin96("8934588012228", out _));
        Assert.False(PosScanCodes.TryGtinFromSgtin96("E2801160600002054C4D17B3", out _)); // TID / EPC không phải SGTIN
    }

    [Fact]
    public void Gtin14_dau_0_thu_ca_ma_ean13()
    {
        Assert.Contains("8934588012228", PosScanCodes.LookupKeys("08934588012228"));
        Assert.Equal('8', PosScanCodes.CheckDigit("893458801222"));
    }

    [Fact]
    public async Task Quet_lo_ma_cong_so_dem_ma_thung_the_rfid_ma_la()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        Guid lonId, dvId;
        await using (var db = Fx.NewDb())
        {
            var lon = new PosProduct
            {
                Id = Guid.NewGuid(), StoreId = store, ProductCode = "BIA01", Barcode = "8934588012228",
                Name = "Bia lon", BaseUnitName = "Lon", BasePrice = 18000, OnHandQty = 50,
                IsDirectSale = true, IsActive = true,
            };
            var dv = new PosProduct
            {
                Id = Guid.NewGuid(), StoreId = store, ProductCode = "DV01", Barcode = "2000000000015",
                Name = "Rửa xe", BaseUnitName = "Lần", ProductType = PosProductType.Service,
                IsDirectSale = true, IsActive = true,
            };
            db.PosProducts.AddRange(lon, dv);
            db.PosProductUnits.Add(new PosProductUnit
            {
                Id = Guid.NewGuid(), StoreId = store, ProductId = lon.Id, UnitName = "Thùng",
                ConversionRate = 24, Barcode = "8934588012235", IsActive = true,
            });
            db.PosProductSerials.Add(new PosProductSerial
            {
                Id = Guid.NewGuid(), StoreId = store, ProductId = lon.Id, SerialNumber = "SN-1",
                TagCode = "E2801160600002054C4D17B3",
            });
            await db.SaveChangesAsync();
            lonId = lon.Id;
            dvId = dv.Id;
        }

        await using var db2 = Fx.NewDb();
        var ctl = PosPgFixture.As(new PosStockCountsController(db2), store);
        var c = Data(await ctl.CreateCount(new PosStockCountsController.CreateStockCountDto("KK quét", null)));

        // 3 lon + 1 thùng (24) + 1 thẻ RFID gắn seri lon + mã lạ ×2 + dịch vụ (không quản lý tồn).
        var r = Data(await ctl.ScanCodes(c.Id, new PosStockCountsController.ScanCountCodesDto(
        [
            "8934588012228", "8934588012228", " 8934588012228 ", "8934588012235",
            "e2801160600002054c4d17b3", "LA-123", "LA-123", "2000000000015",
        ], "T1")));
        var line = Assert.Single(r.Count.Lines);
        Assert.Equal(lonId, line.ProductId);
        Assert.Equal(3 + 24 + 1, line.CountedQty);
        Assert.Equal(50, line.SystemQty);
        Assert.True(line.IsChecked);
        Assert.Equal(2, r.Unknown["LA-123"]);
        Assert.Equal(1, r.NotTracked["2000000000015"]);
        Assert.Equal(5, r.MatchedCodes);
        Assert.DoesNotContain(r.Count.Lines, l => l.ProductId == dvId);

        // Lô sau cộng tiếp vào dòng đã có.
        var r2 = Data(await ctl.ScanCodes(c.Id, new PosStockCountsController.ScanCountCodesDto(
            ["8934588012228"], "T1")));
        Assert.Equal(29, Assert.Single(r2.Count.Lines).CountedQty);
    }
}

using Xunit;
using ZKTecoADMS.Api.Services.Assets;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Tests;

/// <summary>Giá trị còn lại tài sản (khấu hao đường thẳng).</summary>
public class AssetValuationTests
{
    static readonly DateTime Now = new(2026, 9, 28, 0, 0, 0, DateTimeKind.Utc);

    [Fact]
    public void Khau_hao_duong_thang_theo_so_nam_da_dung()
    {
        // 20%/năm, dùng đúng 2 năm → còn 60%
        var a = new Asset { PurchasePrice = 10_000_000, DepreciationRate = 20, PurchaseDate = Now.AddDays(-730), Quantity = 2, Status = AssetStatus.Active };
        Assert.Equal(6_000_000m, AssetValuation.UnitBookValue(a, Now));
        Assert.Equal(12_000_000m, AssetValuation.BookValue(a, Now));
    }

    [Fact]
    public void Khau_hao_het_thi_bang_0_khong_am()
    {
        var a = new Asset { PurchasePrice = 5_000_000, DepreciationRate = 50, PurchaseDate = Now.AddYears(-5), Status = AssetStatus.Active };
        Assert.Equal(0m, AssetValuation.UnitBookValue(a, Now));
    }

    [Fact]
    public void Khong_co_ty_le_dung_gia_tri_nhap_tay_hoac_gia_mua()
    {
        Assert.Equal(3_000_000m, AssetValuation.UnitBookValue(
            new Asset { PurchasePrice = 5_000_000, CurrentValue = 3_000_000, Status = AssetStatus.Active }, Now));
        Assert.Equal(5_000_000m, AssetValuation.UnitBookValue(
            new Asset { PurchasePrice = 5_000_000, Status = AssetStatus.InStock }, Now));
    }

    [Theory]
    [InlineData(AssetStatus.Disposed)]
    [InlineData(AssetStatus.Lost)]
    public void Thanh_ly_hoac_mat_gia_tri_bang_0(AssetStatus status) =>
        Assert.Equal(0m, AssetValuation.UnitBookValue(new Asset { PurchasePrice = 1_000_000, Status = status }, Now));

    [Fact]
    public void Khau_hao_trong_ky_theo_so_ngay()
    {
        // 36,5 triệu, 100%/năm → 100.000 đ/ngày; 2 cái.
        var bought = new DateTime(2026, 1, 1, 0, 0, 0, DateTimeKind.Utc);
        var a = new Asset { PurchasePrice = 36_500_000, DepreciationRate = 100, PurchaseDate = bought, Quantity = 2, Status = AssetStatus.Active };
        Assert.Equal(6_200_000m, AssetValuation.PeriodDepreciation(a, new DateTime(2026, 10, 1), new DateTime(2026, 11, 1)));
        // Kỳ bắt đầu trước ngày mua: chỉ tính từ ngày mua.
        Assert.Equal(200_000m, AssetValuation.PeriodDepreciation(a, new DateTime(2025, 12, 1), bought.AddDays(1)));
        // Trước ngày mua / đã khấu hao hết / đã thanh lý / không có tỷ lệ = 0.
        Assert.Equal(0m, AssetValuation.PeriodDepreciation(a, new DateTime(2025, 1, 1), new DateTime(2025, 12, 31)));
        Assert.Equal(0m, AssetValuation.PeriodDepreciation(a, new DateTime(2027, 6, 1), new DateTime(2027, 7, 1)));
        Assert.Equal(0m, AssetValuation.PeriodDepreciation(
            new Asset { PurchasePrice = 36_500_000, DepreciationRate = 100, PurchaseDate = bought, Quantity = 1, Status = AssetStatus.Disposed },
            new DateTime(2026, 10, 1), new DateTime(2026, 11, 1)));
        Assert.Equal(0m, AssetValuation.PeriodDepreciation(
            new Asset { PurchasePrice = 36_500_000, PurchaseDate = bought, Quantity = 1, Status = AssetStatus.Active },
            new DateTime(2026, 10, 1), new DateTime(2026, 11, 1)));
    }
}

using Xunit;
using ZKTecoADMS.Api.Controllers;

namespace ZKTecoADMS.Tests;

/// <summary>Tìm catalog mẫu gõ không dấu vẫn khớp tên tiếng Việt.</summary>
public class SampleCatalogSearchTests
{
    [Theory]
    [InlineData("Gói tập 10 buổi", "goi tap")]
    [InlineData("Đồ ăn vặt", "do an")]
    [InlineData("THẺ THÁNG", "the thang")]
    [InlineData("Gói tập 10 buổi", "gói tập")]
    public void Khong_dau_van_khop(string name, string search)
    {
        var folded = PosProductsController.FoldVietnamese(name);
        Assert.Contains(PosProductsController.FoldVietnamese(search), folded);
    }

    [Fact]
    public void Nhieu_tu_khong_lien_nhau_van_khop()
    {
        var terms = PosProductsController.FoldVietnamese("goi buoi").Split(' ');
        Assert.True(PosProductsController.SampleMatches(terms, "Gói 10 buổi PT", null, "Gói tập", null));
        Assert.False(PosProductsController.SampleMatches(terms, "Membership tháng", null, "Membership", null));
    }

    [Fact]
    public void Null_tra_chuoi_rong()
    {
        Assert.Equal("", PosProductsController.FoldVietnamese(null));
    }
}

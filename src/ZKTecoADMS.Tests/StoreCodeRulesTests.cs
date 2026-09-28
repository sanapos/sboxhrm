using Xunit;
using ZKTecoADMS.Application.Services;

namespace ZKTecoADMS.Tests;

/// <summary>Mã cửa hàng: chuẩn hoá tên tiếng Việt, mã bị giữ, gợi ý mã còn trống.</summary>
public class StoreCodeRulesTests
{
    [Theory]
    [InlineData("Cà Phê Đất Việt", "caphedatviet")]
    [InlineData("  Shop-ABC 123 ", "shopabc123")]
    [InlineData("Nhà hàng Hương Quê Miền Tây Nam Bộ", "nhahanghuongquemient")]
    public void Chuan_hoa_ten(string input, string expected) =>
        Assert.Equal(expected, StoreCodeRules.Sanitize(input));

    [Fact]
    public void Ma_he_thong_va_qua_ngan_bi_chan()
    {
        Assert.NotNull(StoreCodeRules.FormatError("admin"));
        Assert.NotNull(StoreCodeRules.FormatError("a"));
        Assert.Null(StoreCodeRules.FormatError("sanapos"));
    }

    [Fact]
    public void Goi_y_bo_qua_ma_da_dung()
    {
        var taken = new HashSet<string> { "caphe", "caphe1", "cp1" };
        var s = StoreCodeRules.Suggest("caphe", "Cà phê", "Hà Nội", taken.Contains);
        Assert.Equal(3, s.Count);
        Assert.DoesNotContain(s, taken.Contains);
        Assert.All(s, c => Assert.Null(StoreCodeRules.FormatError(c)));
    }
}

using Xunit;
using ZKTecoADMS.Api.Controllers;

namespace ZKTecoADMS.Tests;

/// <summary>Một mã vạch quét ra nhiều độ dài (UPC-A / EAN-13 / GTIN-14) vẫn phải khớp cùng hàng.</summary>
public class PosGtinTests
{
    [Fact]
    public void Ean13_MatchesUpcAAndGtin14()
    {
        var v = PosGtin.Variants("0012345678905");
        Assert.Contains("012345678905", v);      // UPC-A: bỏ 1 số 0 đầu
        Assert.Contains("00012345678905", v);    // GTIN-14
        Assert.Contains("0012345678905", v);
    }

    [Fact]
    public void UpcA_MatchesEan13Stored()
    {
        var v = PosGtin.Variants("012345678905");
        Assert.Contains("0012345678905", v);
    }

    [Fact]
    public void Gtin14_MatchesEan13Stored()
    {
        var v = PosGtin.Variants("08934563138165");
        Assert.Contains("8934563138165", v);
    }

    [Theory]
    [InlineData("HH00001")]
    [InlineData("  AbC-123 ")]
    [InlineData("12345")]            // quá ngắn: không đệm số 0
    [InlineData("123456789012345")]  // quá dài
    public void NonGtin_StaysAsIs(string code)
    {
        var v = PosGtin.Variants(code);
        Assert.Single(v);
        Assert.Equal(code.Trim().ToLowerInvariant(), v[0]);
    }

    [Fact]
    public void AllZeros_DoesNotExplode()
    {
        Assert.Single(PosGtin.Variants("0000000000000"));
    }

    [Fact]
    public void DifferentNumbers_DoNotCollide()
    {
        Assert.DoesNotContain("8934563138165", PosGtin.Variants("8934563138166"));
    }
}

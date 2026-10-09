using Xunit;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Tests.Pos;

public class PosQuoteStageMathTests
{
    static PosQuotePaymentStage St(string title, decimal? pct, decimal amount = 0) =>
        new() { Id = Guid.NewGuid(), Title = title, Percent = pct, Amount = amount };

    [Fact]
    public void Coc_tinh_tren_truoc_VAT_dot_cuoi_nhan_phan_con_lai()
    {
        var a = PosQuoteStageMath.Amounts(
            [St("Đặt cọc ký hợp đồng", 30), St("Giao hàng", 50), St("Nghiệm thu", 20)],
            total: 103_680_000, preVat: 96_000_000);
        Assert.Equal([28_800_000m, 51_840_000m, 23_040_000m], a);
        Assert.Equal(103_680_000m, a.Sum());
    }

    [Fact]
    public void Khong_du_100_phan_tram_thi_khong_don_dot_cuoi()
    {
        var a = PosQuoteStageMath.Amounts(
            [St("Đặt cọc", 30), St("Giao hàng", 50)],
            total: 103_680_000, preVat: 96_000_000);
        Assert.Equal([28_800_000m, 51_840_000m], a);
    }

    [Fact]
    public void Dot_nhap_so_tien_giu_nguyen_va_chi_coc_dau_tien_tinh_truoc_VAT()
    {
        var a = PosQuoteStageMath.Amounts(
            [St("Cọc lần 1", 10), St("Cọc bổ sung", 10), St("Lắp đặt", null, 5_000_000)],
            total: 110_000_000, preVat: 100_000_000);
        Assert.Equal([10_000_000m, 11_000_000m, 5_000_000m], a);
    }

    [Fact]
    public void Khong_co_dot_coc_thi_tinh_tren_tong_cong()
    {
        var a = PosQuoteStageMath.Amounts(
            [St("Đợt 1", 40), St("Đợt 2", 60)],
            total: 103_680_000, preVat: 96_000_000);
        Assert.Equal([41_472_000m, 62_208_000m], a);
    }
}

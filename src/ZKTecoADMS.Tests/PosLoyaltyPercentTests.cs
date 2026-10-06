using Xunit;
using ZKTecoADMS.Api.Controllers;
using static ZKTecoADMS.Api.Controllers.PosCustomerFinanceHelper;

namespace ZKTecoADMS.Tests;

/// <summary>Tích điểm theo % từng sản phẩm (VD hộp thịt 100k tích 20% = 20.000đ) + mức chung cho hàng còn lại.</summary>
public class PosLoyaltyPercentTests
{
    static readonly PosLoyaltyRates Rates = new(true, 10_000m, 100m, 100m); // 10.000đ = 1 điểm; 1 điểm = 100đ

    [Fact]
    public void Hop_thit_100k_tich_20_phan_tram_duoc_20k()
    {
        var pts = CalcPointsEarn(100_000m, [new EarnLine(100_000m, 20m)], Rates);
        Assert.Equal(200m, pts);                 // 200 điểm
        Assert.Equal(20_000m, pts * Rates.RedeemValue); // = 20.000đ dùng cho đơn sau
    }

    [Fact]
    public void Hang_khong_co_phan_tram_tich_theo_muc_chung()
    {
        // 100k hộp thịt 20% (=200 điểm) + 50k hàng thường (50.000 / 10.000 = 5 điểm)
        var pts = CalcPointsEarn(150_000m, [new EarnLine(100_000m, 20m), new EarnLine(50_000m, null)], Rates);
        Assert.Equal(205m, pts);
    }

    [Fact]
    public void Giam_gia_don_chia_lai_theo_dong()
    {
        // Đơn 200k giảm còn 150k (75%): hộp thịt 100k → tính trên 75k × 20% = 15.000đ = 150 điểm;
        // hàng thường 100k → 75k → 7 điểm.
        var pts = CalcPointsEarn(150_000m, [new EarnLine(100_000m, 20m), new EarnLine(100_000m, null)], Rates);
        Assert.Equal(157m, pts);
    }

    [Fact]
    public void Khong_co_hang_phan_tram_giu_nguyen_cach_cu()
    {
        Assert.Equal(CalcPointsEarn(123_000m, Rates),
            CalcPointsEarn(123_000m, [new EarnLine(123_000m, null)], Rates));
    }

    [Fact]
    public void Tat_tich_diem_thi_khong_tich()
    {
        var off = Rates with { Enabled = false };
        Assert.Equal(0m, CalcPointsEarn(100_000m, [new EarnLine(100_000m, 20m)], off));
    }
}

using Xunit;
using ZKTecoADMS.Application.Helpers;

namespace ZKTecoADMS.Tests;

/// <summary>
/// Vào trễ quá «Giới hạn đi trễ» vẫn khớp ca và tính trễ đủ phút (phạt tự động, báo cáo) —
/// giống bộ máy tính công payroll_engine. Chỉ cách giờ vào ca quá 180 phút mới không khớp.
/// </summary>
public class ShiftMatchLateBeyondMaxTests
{
    static readonly ShiftMatchHelper.Candidate Ca = new(
        Guid.NewGuid(), new TimeSpan(8, 0, 0), new TimeSpan(17, 0, 0),
        LateGraceMinutes: 5, MaximumAllowedLateMinutes: 15);

    [Theory]
    [InlineData(8, 14, 14)]
    [InlineData(8, 19, 19)]
    [InlineData(10, 30, 150)]
    public void Tre_qua_gioi_han_van_tinh_du_phut(int h, int m, int late)
    {
        var fit = ShiftMatchHelper.FindBestForCheckIn([Ca], new TimeSpan(h, m, 0));
        Assert.NotNull(fit);
        Assert.Equal(late, fit!.EffectiveLateIn);
    }

    [Fact]
    public void Qua_180_phut_khong_khop_ca()
        => Assert.Null(ShiftMatchHelper.FindBestForCheckIn([Ca], new TimeSpan(11, 1, 0)));

    [Fact]
    public void Tre_19_phut_kem_ve_som_7_phut()
    {
        var fit = ShiftMatchHelper.FindBest([Ca], new TimeSpan(8, 19, 0), new TimeSpan(16, 53, 0));
        Assert.NotNull(fit);
        Assert.Equal(19, fit!.EffectiveLateIn);
        Assert.Equal(7, fit.EffectiveEarlyOut);
    }
}

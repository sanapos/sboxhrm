using Xunit;
using ZKTecoADMS.Application.Services;

namespace ZKTecoADMS.Tests;

/// <summary>Định mức nhân sự theo ca + giờ ca + nghỉ phép phủ ca.</summary>
public class ShiftCoverageRulesTests
{
    [Theory]
    [InlineData(1, 3, 6, 0, ShiftCoverageRules.Short)]
    [InlineData(3, 3, 6, 2, ShiftCoverageRules.Tight)]  // vừa đủ tối thiểu, ngưỡng cảnh báo 2
    [InlineData(5, 3, 6, 2, ShiftCoverageRules.Ok)]
    [InlineData(6, 3, 6, 0, ShiftCoverageRules.Full)]
    [InlineData(7, 3, 6, 0, ShiftCoverageRules.Over)]
    [InlineData(4, 0, 0, 0, ShiftCoverageRules.Ok)]     // không giới hạn tối đa
    public void Trang_thai_dinh_muc(int effective, int min, int max, int warn, string expected) =>
        Assert.Equal(expected, ShiftCoverageRules.Status(effective, min, max, warn));

    [Fact]
    public void Khong_co_dinh_muc_va_so_cho_con_lai()
    {
        Assert.Equal(ShiftCoverageRules.NoQuota, ShiftCoverageRules.Status(2, 0, 0, hasQuota: false));
        Assert.Equal(2, ShiftCoverageRules.Remaining(4, 6));
        Assert.Equal(0, ShiftCoverageRules.Remaining(8, 6));
        Assert.Null(ShiftCoverageRules.Remaining(8, 0));
    }

    [Fact]
    public void Gio_ca_tru_nghi_va_ca_qua_dem()
    {
        Assert.Equal(8, ShiftCoverageRules.ShiftHours(new TimeSpan(8, 0, 0), new TimeSpan(17, 0, 0), 60));
        Assert.Equal(8, ShiftCoverageRules.ShiftHours(new TimeSpan(22, 0, 0), new TimeSpan(6, 0, 0)));
    }

    [Fact]
    public void Nghi_phep_phu_ca_theo_ngay_va_ca()
    {
        var ca1 = Guid.NewGuid();
        var ca2 = Guid.NewGuid();
        var from = new DateTime(2026, 9, 28);
        Assert.True(ShiftCoverageRules.LeaveCovers(from, from.AddDays(2), [ca1], from.AddDays(1), ca1));
        Assert.False(ShiftCoverageRules.LeaveCovers(from, from.AddDays(2), [ca1], from.AddDays(1), ca2));
        Assert.False(ShiftCoverageRules.LeaveCovers(from, from.AddDays(2), [ca1], from.AddDays(3), ca1));
        Assert.True(ShiftCoverageRules.LeaveCovers(from, from, [], from, ca2)); // không chọn ca = cả ngày
    }
}

using Xunit;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Tests;

/// <summary>Ngày lễ mặc định khi đăng ký cửa hàng: Tết / Giỗ Tổ theo âm lịch của đúng năm (trước ghi cứng 2025).</summary>
public class VietnamHolidaysTests
{
    static DateTime On(int year, string name) =>
        VietnamHolidays.GetDefaultHolidays(year).Single(h => h.Name == name).Date;

    [Theory]
    [InlineData(2025, "2025-01-28", "2025-01-29", "2025-04-07")]
    [InlineData(2026, "2026-02-16", "2026-02-17", "2026-04-26")]
    [InlineData(2027, "2027-02-05", "2027-02-06", "2027-04-16")]
    // 2023 nhuận tháng 2 → Giỗ Tổ lùi một tháng âm.
    [InlineData(2023, "2023-01-21", "2023-01-22", "2023-04-29")]
    public void TetAndHungKings_FollowLunarCalendarOfThatYear(int year, string eve, string day1, string hungKings)
    {
        Assert.Equal(DateTime.Parse(eve), On(year, "Tết Nguyên Đán (Giao Thừa)"));
        Assert.Equal(DateTime.Parse(day1), On(year, "Tết Nguyên Đán (Mùng 1)"));
        Assert.Equal(DateTime.Parse(day1).AddDays(3), On(year, "Tết Nguyên Đán (Mùng 4)"));
        Assert.Equal(DateTime.Parse(hungKings), On(year, "Giỗ Tổ Hùng Vương"));
    }

    [Fact]
    public void FixedHolidays_AndCount()
    {
        var list = VietnamHolidays.GetDefaultHolidays(2026);
        Assert.Equal(10, list.Count);
        Assert.Equal(list.Count, list.Select(h => h.Date).Distinct().Count());
        Assert.Equal(new DateTime(2026, 9, 2), On(2026, "Ngày Quốc Khánh"));
        Assert.All(list, h => Assert.Equal(2026, h.Date.Year));
    }
}

using Xunit;
using ZKTecoADMS.Application.Services;

namespace ZKTecoADMS.Tests;

public class PosHotelNightMathTests
{
    /// <summary>Giờ Việt Nam → UTC.</summary>
    static DateTime Vn(int day, int h, int m = 0) => new DateTime(2026, 9, day, h, m, 0, DateTimeKind.Utc).AddHours(-7);

    [Theory]
    [InlineData(1, 14, 0, 2, 11, 0, 1.0)]   // nhận 14h, trả 11h hôm sau → 1 đêm
    [InlineData(1, 22, 0, 2, 12, 20, 1.0)]  // trả 12:20 — trong ân hạn 30 phút
    [InlineData(1, 14, 0, 2, 15, 0, 1.5)]   // trả muộn 15h (≤ 18h) → +½
    [InlineData(1, 14, 0, 2, 19, 0, 2.0)]   // trả sau 18h → thêm 1 đêm
    [InlineData(1, 10, 0, 2, 12, 0, 1.5)]   // nhận sớm 10h → +½
    [InlineData(1, 1, 0, 1, 12, 0, 1.0)]    // đến 1h sáng → tính đêm hôm trước, trả 12h cùng ngày
    [InlineData(1, 14, 0, 4, 11, 0, 3.0)]   // 3 đêm
    [InlineData(1, 14, 0, 1, 16, 0, 1.0)]   // ở vài giờ trong ngày → tối thiểu 1 đêm
    public void Nights_follow_check_in_out_rules(int d1, int h1, int m1, int d2, int h2, int m2, double expected)
    {
        Assert.Equal((decimal)expected, PosHotelNightMath.Nights(Vn(d1, h1, m1), Vn(d2, h2, m2)));
    }

    [Fact]
    public void Store_policy_from_extra_json()
    {
        var p = HotelStayPolicy.Parse("""{"hotel":{"checkIn":"13:00","checkOut":"11:00","lateHalfUntil":"17:00","graceMinutes":0}}""");
        Assert.Equal((13 * 60, 11 * 60, 17 * 60, 0), (p.CheckInMinute, p.CheckOutMinute, p.LateHalfUntilMinute, p.GraceMinutes));
        // Trả 11:30 với giờ trả 11:00, không ân hạn → +½.
        Assert.Equal(1.5m, PosHotelNightMath.Nights(Vn(1, 13), Vn(2, 11, 30), p));
        Assert.False(HotelStayPolicy.Parse("""{"hotel":{"nightMode":false}}""").NightMode);
        Assert.True(HotelStayPolicy.Parse(null).NightMode);
    }
}

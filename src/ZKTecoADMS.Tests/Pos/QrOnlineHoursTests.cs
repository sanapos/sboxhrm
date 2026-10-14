using Xunit;
using ZKTecoADMS.Api.Services;

namespace ZKTecoADMS.Tests.Pos;

/// <summary>Giờ nhận đơn online (giờ Việt Nam): trong / ngoài giờ, ca qua đêm, đặt trước.</summary>
public class QrOnlineHoursTests
{
    static QrOrderLockHelper.Options Opt(string? open, string? close, bool enabled = true, string? mode = null) =>
        QrOrderLockHelper.Parse(
            "{\"qrOrder\":{\"onlineHoursEnabled\":" + (enabled ? "true" : "false") +
            (open == null ? "" : ",\"onlineOpenTime\":\"" + open + "\"") +
            (close == null ? "" : ",\"onlineCloseTime\":\"" + close + "\"") +
            (mode == null ? "" : ",\"onlineAfterHoursMode\":\"" + mode + "\"") + "}}");

    // Giờ Việt Nam hh:mm → UTC (VN = UTC+7).
    static DateTime Vn(int h, int m) => new DateTime(2026, 10, 14, h, m, 0, DateTimeKind.Utc).AddHours(-7);

    [Theory]
    [InlineData(7, 59, false)]
    [InlineData(8, 0, true)]
    [InlineData(21, 59, true)]
    [InlineData(22, 0, false)]
    [InlineData(23, 30, false)]
    public void Day_shift_8_to_22(int h, int m, bool openNow)
    {
        var s = QrOrderLockHelper.OnlineHours(Opt("08:00", "22:00"), Vn(h, m));
        Assert.True(s.Enabled);
        Assert.Equal(openNow, s.OpenNow);
        Assert.Equal(!openNow, s.AfterHours);
        Assert.Equal("08:00–22:00", s.RangeText);
    }

    [Theory]
    [InlineData(17, 59, false)]
    [InlineData(18, 0, true)]
    [InlineData(23, 59, true)]
    [InlineData(1, 30, true)]
    [InlineData(2, 0, false)]
    [InlineData(12, 0, false)]
    public void Overnight_shift_18_to_02(int h, int m, bool openNow)
    {
        var s = QrOrderLockHelper.OnlineHours(Opt("18:00", "02:00"), Vn(h, m));
        Assert.Equal(openNow, s.OpenNow);
    }

    [Fact]
    public void Disabled_or_invalid_means_always_open()
    {
        Assert.False(QrOrderLockHelper.OnlineHours(Opt("08:00", "22:00", enabled: false), Vn(3, 0)).AfterHours);
        Assert.False(QrOrderLockHelper.OnlineHours(Opt("8h", "22:00"), Vn(3, 0)).AfterHours);
        Assert.False(QrOrderLockHelper.OnlineHours(Opt(null, null), Vn(3, 0)).AfterHours);
        Assert.False(QrOrderLockHelper.OnlineHours(default, Vn(3, 0)).AfterHours);
        Assert.True(QrOrderLockHelper.OnlineHours(Opt("00:00", "24:00"), Vn(3, 0)).OpenNow);
    }

    [Fact]
    public void After_hours_mode_block_or_preorder()
    {
        Assert.False(QrOrderLockHelper.OnlineHours(Opt("08:00", "22:00"), Vn(23, 0)).AllowPreorder);
        Assert.False(QrOrderLockHelper.OnlineHours(Opt("08:00", "22:00", mode: "block"), Vn(23, 0)).AllowPreorder);
        Assert.True(QrOrderLockHelper.OnlineHours(Opt("08:00", "22:00", mode: "preorder"), Vn(23, 0)).AllowPreorder);
    }
}

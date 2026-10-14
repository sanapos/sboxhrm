using Xunit;
using ZKTecoADMS.Api.Services;

namespace ZKTecoADMS.Tests.Pos;

/// <summary>Giờ nhận đơn online (giờ Việt Nam): một khung mọi ngày, lịch tuần nhiều ca, ngày nghỉ, ca qua đêm.</summary>
public class QrOnlineHoursTests
{
    static QrOrderLockHelper.Options Opt(
        string? open = null, string? close = null, bool enabled = true, string? mode = null, string? schedule = null) =>
        QrOrderLockHelper.Parse(
            "{\"qrOrder\":{\"onlineHoursEnabled\":" + (enabled ? "true" : "false") +
            (open == null ? "" : ",\"onlineOpenTime\":\"" + open + "\"") +
            (close == null ? "" : ",\"onlineCloseTime\":\"" + close + "\"") +
            (mode == null ? "" : ",\"onlineAfterHoursMode\":\"" + mode + "\"") +
            (schedule == null ? "" : ",\"onlineSchedule\":" + schedule) + "}}");

    // Giờ Việt Nam → UTC (VN = UTC+7). 2026-10-12 Thứ Hai … 2026-10-18 Chủ nhật.
    static DateTime Vn(int day, int h, int m = 0) => new DateTime(2026, 10, day, h, m, 0, DateTimeKind.Utc).AddHours(-7);
    const int Mon = 12, Tue = 13, Wed = 14, Fri = 16, Sat = 17, Sun = 18;

    [Theory]
    [InlineData(7, 59, false, "08:00")]
    [InlineData(8, 0, true, "08:00 ngày mai")]
    [InlineData(21, 59, true, "08:00 ngày mai")]
    [InlineData(22, 0, false, "08:00 ngày mai")]
    public void Same_hours_every_day(int h, int m, bool openNow, string next)
    {
        var s = QrOrderLockHelper.OnlineHours(Opt("08:00", "22:00"), Vn(Wed, h, m));
        Assert.True(s.Enabled);
        Assert.Equal(openNow, s.OpenNow);
        Assert.Equal("08:00–22:00", s.TodayText);
        Assert.Equal(next, s.NextOpen);
    }

    [Theory]
    [InlineData(17, 59, false)]
    [InlineData(18, 0, true)]
    [InlineData(1, 30, true)] // ca tối hôm trước kéo qua đêm
    [InlineData(2, 0, false)]
    [InlineData(12, 0, false)]
    public void Overnight_every_day(int h, int m, bool openNow) =>
        Assert.Equal(openNow, QrOrderLockHelper.OnlineHours(Opt("18:00", "02:00"), Vn(Wed, h, m)).OpenNow);

    const string TwoShifts =
        "{\"mon\":[],\"tue\":[[\"08:00\",\"22:00\"]],\"wed\":[[\"08:00\",\"11:00\"],[\"17:00\",\"22:00\"]]," +
        "\"thu\":[[\"08:00\",\"22:00\"]],\"fri\":[[\"18:00\",\"02:00\"]],\"sat\":[],\"sun\":[[\"08:00\",\"22:00\"]]}";

    [Theory]
    [InlineData(9, true, "17:00")]
    [InlineData(12, false, "17:00")]
    [InlineData(17, true, "08:00 ngày mai")]
    [InlineData(23, false, "08:00 ngày mai")]
    public void Two_shifts_a_day(int h, bool openNow, string next)
    {
        var s = QrOrderLockHelper.OnlineHours(Opt(schedule: TwoShifts), Vn(Wed, h));
        Assert.Equal(openNow, s.OpenNow);
        Assert.Equal("08:00–11:00, 17:00–22:00", s.TodayText);
        Assert.Equal(next, s.NextOpen);
    }

    [Fact]
    public void Day_off_monday()
    {
        var s = QrOrderLockHelper.OnlineHours(Opt(schedule: TwoShifts), Vn(Mon, 10));
        Assert.False(s.OpenNow);
        Assert.True(s.ClosedToday);
        Assert.Equal("08:00 ngày mai", s.NextOpen);
        Assert.Contains("Hôm nay quán nghỉ", s.BlockText);
        // Chủ nhật tối → thứ Hai nghỉ → mở lại Thứ Ba.
        Assert.Equal("08:00 Thứ Ba", QrOrderLockHelper.OnlineHours(Opt(schedule: TwoShifts), Vn(Sun, 23)).NextOpen);
    }

    [Fact]
    public void Friday_overnight_into_saturday_day_off()
    {
        Assert.True(QrOrderLockHelper.OnlineHours(Opt(schedule: TwoShifts), Vn(Fri, 20)).OpenNow);
        Assert.True(QrOrderLockHelper.OnlineHours(Opt(schedule: TwoShifts), Vn(Sat, 1)).OpenNow);
        var sat = QrOrderLockHelper.OnlineHours(Opt(schedule: TwoShifts), Vn(Sat, 3));
        Assert.False(sat.OpenNow);
        Assert.Equal("08:00 ngày mai", sat.NextOpen);
    }

    [Fact]
    public void Whole_week_closed_means_paused()
    {
        var s = QrOrderLockHelper.OnlineHours(
            Opt(schedule: "{\"mon\":[],\"tue\":[],\"wed\":[],\"thu\":[],\"fri\":[],\"sat\":[],\"sun\":[]}"), Vn(Tue, 10));
        Assert.True(s.AfterHours);
        Assert.Equal("", s.NextOpen);
        Assert.Contains("tạm ngưng", s.BlockText);
    }

    [Fact]
    public void Disabled_or_invalid_means_always_open()
    {
        Assert.False(QrOrderLockHelper.OnlineHours(Opt("08:00", "22:00", enabled: false), Vn(Wed, 3)).AfterHours);
        Assert.False(QrOrderLockHelper.OnlineHours(Opt("8h", "22:00"), Vn(Wed, 3)).AfterHours);
        Assert.False(QrOrderLockHelper.OnlineHours(Opt(), Vn(Wed, 3)).AfterHours);
        Assert.False(QrOrderLockHelper.OnlineHours(default, Vn(Wed, 3)).AfterHours);
        Assert.True(QrOrderLockHelper.OnlineHours(Opt("00:00", "24:00"), Vn(Wed, 3)).OpenNow);
    }

    [Fact]
    public void After_hours_mode_block_or_preorder()
    {
        Assert.False(QrOrderLockHelper.OnlineHours(Opt("08:00", "22:00"), Vn(Wed, 23)).AllowPreorder);
        Assert.True(QrOrderLockHelper.OnlineHours(Opt("08:00", "22:00", mode: "preorder"), Vn(Wed, 23)).AllowPreorder);
    }
}

using Xunit;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Tests;

/// <summary>LX35 (Anyka AK3750, PushVersion 3.0.1): nhận đúng nhóm máy, lệnh tải chấm công đúng định dạng.</summary>
public class Lx35PushLiteTests
{
    [Theory]
    [InlineData(null, "Unknown", "3.0.1")]          // chỉ có pushver từ handshake
    [InlineData("", "", "3.0.1")]
    [InlineData("AK3750WIFI_TFT", "Ver 6.60 May 19 2023", null)]
    public void Lx35_is_push_lite_not_pull_deny(string? platform, string? fw, string? pushVer) =>
        Assert.Equal(AdmsEngineProfiles.PushLite, AdmsEngineProfiles.ResolveProfile(platform, fw, "1313254900299", pushVer));

    [Fact]
    public void Unknown_device_with_131_serial_is_not_seeded_pull_deny()
    {
        Assert.Equal(AdmsEngineProfiles.Default, AdmsEngineProfiles.ResolveProfile(null, "Unknown", "1313254900299"));
        // Máy đã biết firmware OEM ZLM31 vẫn giữ PullDeny như cũ.
        Assert.Equal(AdmsEngineProfiles.PullDeny, AdmsEngineProfiles.ResolveProfile(null, "ZLM31-FXO1-3.1.8", "1313254900327"));
        // Các máy khác không đổi.
        Assert.Equal(AdmsEngineProfiles.TftLegacy, AdmsEngineProfiles.ResolveProfile("ZLM60_TFT", "Ver 8.0.4.3-20230515", "1313254901225", "2.4.1"));
        Assert.Equal(AdmsEngineProfiles.AndroidVisibleLight, AdmsEngineProfiles.ResolveProfile("ZAM70_TFT", "ZAM70-NF24HA-3.3.12-OCM-2535-Ver1.1.0", "1313254900907"));
    }

    [Fact]
    public void Leaving_pull_deny_reopens_seeded_flags()
    {
        var info = new DeviceInfo { EngineProfile = AdmsEngineProfiles.PullDeny, SupportsUserQuery = false, SupportsEnrollFingerprint = false, PreferStampSync = true };
        AdmsEngineProfiles.ApplyProfileDefaults(info, AdmsEngineProfiles.PushLite);
        Assert.True(info.SupportsUserQuery);
        Assert.True(info.SupportsAttendanceQuery);
        Assert.False(info.PreferStampSync);
        Assert.Null(info.SupportsEnrollFingerprint);
    }

    [Fact]
    public void Attendance_query_time_format()
    {
        var s = new DateTime(2026, 9, 1, 0, 0, 0);
        var e = new DateTime(2026, 10, 2, 23, 59, 59);
        Assert.Equal("DATA QUERY ATTLOG StartTime=2026-09-01 00:00:00\tEndTime=2026-10-02 23:59:59",
            ClockCommandBuilder.BuildGetAttendanceCommand(s, e, spaceSeparated: true));
        var t = ClockCommandBuilder.BuildGetAttendanceCommand(s, e);
        Assert.Equal("DATA QUERY ATTLOG StartTime=2026-09-01T00:00:00\tEndTime=2026-10-02T23:59:59", t);
        Assert.True(ClockCommandBuilder.TryParseAttendanceQuery(t, out var ps, out var pe));
        Assert.Equal(s, ps);
        Assert.Equal(e, pe);
        Assert.False(ClockCommandBuilder.TryParseAttendanceQuery("DATA QUERY USERINFO", out _, out _));
    }
}

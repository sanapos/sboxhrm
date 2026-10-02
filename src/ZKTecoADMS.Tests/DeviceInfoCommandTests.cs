using Xunit;
using ZKTecoADMS.Application.Commands.IClock.DeviceCmdCommand.Strategies;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Tests;

/// <summary>Lệnh «Thông tin máy» (INFO) trên LX35: đọc kết quả, nhận đúng nhóm PushLite, mở lại tải chấm công.</summary>
public class DeviceInfoCommandTests
{
    // Kết quả INFO thật của LX35 cửa hàng demo (SN 1313254900299), 02/10/2026.
    const string Lx35Info = "INFO\n~DeviceName=LX35\nMAC=8C:4F:00:E3:7E:9B\nTransactionCount=3\nFPCount=2\nUserCount=2\n" +
        "MainTime=2026-10-02 23:51:20\nIsSupportFileSyncData=0\n~MaxUserCount=5\nFingerFunOn=1\nIPAddress=192.168.1.54\n" +
        "IsTFT=1\n~Platform=AK3750WIFI_TFT\n~OEMVendor=ZKTECO CO., LTD.\nFPVersion=13\nFWVersion=ZLM31-FXO1-3.1.8\n" +
        "PushVersion=Ver 3.0.1-20230519";

    [Fact]
    public void Info_reply_body_keeps_key_value_lines_only()
    {
        var body = GetDeviceInfoStrategy.InfoBody(Lx35Info);
        Assert.False(body.StartsWith("INFO"));
        Assert.StartsWith("~DeviceName=LX35", body);
        Assert.Contains("~Platform=AK3750WIFI_TFT", body);
        Assert.Contains("~OEMVendor=ZKTECO CO., LTD.", body);
        Assert.Equal(string.Empty, GetDeviceInfoStrategy.InfoBody("INFO"));
        Assert.Equal(string.Empty, GetDeviceInfoStrategy.InfoBody(null));
    }

    [Fact]
    public void Lx35_with_info_is_push_lite_not_pull_deny()
    {
        // SN 131* từng làm máy bị xếp PullDeny; Platform AK37 từ INFO phải thắng.
        Assert.Equal(AdmsEngineProfiles.PushLite, AdmsEngineProfiles.ResolveProfile(
            "AK3750WIFI_TFT", "ZLM31-FXO1-3.1.8", "1313254900299", "Ver 3.0.1-20230519"));
        // Chưa có platform / firmware, chỉ có PushVersion dạng «Ver 3.0.x»
        Assert.Equal(AdmsEngineProfiles.PushLite, AdmsEngineProfiles.ResolveProfile(
            null, null, "1313254900299", "Ver 3.0.1-20230519"));
        Assert.Equal(AdmsEngineProfiles.PushLite, AdmsEngineProfiles.ResolveProfile(
            null, null, "1313254900299", "3.0.1"));
        // Thiếu cả hai → vẫn là PullDeny cũ (không đoán bừa)
        Assert.Equal(AdmsEngineProfiles.PullDeny, AdmsEngineProfiles.ResolveProfile(
            null, "ZLM31-FXO1-3.1.8", "1313254900299", null));
    }

    [Fact]
    public void Leaving_pull_deny_reopens_attendance_and_user_query()
    {
        var info = new DeviceInfo
        {
            EngineProfile = AdmsEngineProfiles.PullDeny,
            SupportsUserQuery = false,
            SupportsAttendanceQuery = false, // học từ -1002 khi lệnh còn gửi ngày dạng «T»
            SupportsEnrollFingerprint = false,
            PreferStampSync = true,
        };
        AdmsEngineProfiles.ApplyProfileDefaults(info, AdmsEngineProfiles.PushLite);
        Assert.Equal(AdmsEngineProfiles.PushLite, info.EngineProfile);
        Assert.True(info.SupportsUserQuery);
        Assert.True(info.SupportsAttendanceQuery);
        Assert.False(info.PreferStampSync);
        Assert.True(AdmsEngineProfiles.UsesSpaceDateTime(info.EngineProfile));
        Assert.Contains("StartTime=2021-01-01 00:00:00", ClockCommandBuilder.BuildGetAttendanceCommand(
            new DateTime(2021, 1, 1), new DateTime(2026, 10, 2, 23, 59, 59), spaceSeparated: true));
    }
}

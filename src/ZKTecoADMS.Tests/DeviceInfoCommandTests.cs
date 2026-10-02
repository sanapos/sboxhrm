using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;
using ZKTecoADMS.Application.Commands.IClock.DeviceCmdCommand.Strategies;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Repositories;
using ZKTecoADMS.Infrastructure.Services.DeviceOperations;

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

    sealed class NoTenant : ITenantProvider
    {
        public Guid? StoreId => null;
        public bool IsSuperAccess => true;
    }

    [Fact]
    public async Task Lx35_rejecting_queries_stays_push_lite_and_fails_fast_with_clear_message()
    {
        var db = new ZKTecoDbContext(new DbContextOptionsBuilder<ZKTecoDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);
        var device = new Device { Id = Guid.NewGuid(), SerialNumber = "1313254900299", DeviceName = "LX35" };
        db.Add(device);
        db.Add(new DeviceInfo
        {
            Id = Guid.NewGuid(), DeviceId = device.Id, Platform = "AK3750WIFI_TFT", FirmwareVersion = "ZLM31-FXO1-3.1.8",
            EngineProfile = AdmsEngineProfiles.PushLite, SupportsUserQuery = true, SupportsAttendanceQuery = true,
        });
        await db.SaveChangesAsync();
        var svc = new DeviceCapabilityService(
            new EfRepository<Device>(db, NullLogger<EfRepository<Device>>.Instance, new NoTenant()),
            new EfRepository<DeviceInfo>(db, NullLogger<EfRepository<DeviceInfo>>.Instance, new NoTenant()),
            NullLogger<DeviceCapabilityService>.Instance);

        // Máy thật trả -1002 cho cả hai lệnh tải (02/10/2026)
        await svc.LearnFromCommandResultAsync(device.Id, DeviceCommandTypes.SyncDeviceUsers, -1002, "DATA");
        await svc.LearnFromCommandResultAsync(device.Id, DeviceCommandTypes.SyncAttendances, -1002, "DATA");
        var info = await db.DeviceInfos.AsNoTracking().SingleAsync();
        Assert.Equal(AdmsEngineProfiles.PushLite, info.EngineProfile); // không bị đẩy về PullDeny
        Assert.False(info.SupportsUserQuery);
        Assert.False(info.SupportsAttendanceQuery);

        // Bấm lại: không gửi lệnh chắc chắn lỗi, trả câu báo rõ ràng
        var explicitCmd = ClockCommandBuilder.BuildGetAttendanceCommand(new DateTime(2021, 1, 1), new DateTime(2026, 10, 2, 23, 59, 59));
        var (att, attMsg) = await svc.ResolveCommandAsync(device.Id, DeviceCommandTypes.SyncAttendances, explicitCommand: explicitCmd);
        Assert.Equal(string.Empty, att);
        Assert.Contains("không cho tải lại lịch sử chấm công", attMsg);
        var (usr, usrMsg) = await svc.ResolveCommandAsync(device.Id, DeviceCommandTypes.SyncDeviceUsers);
        Assert.Equal(string.Empty, usr);
        Assert.Contains("không cho tải danh sách nhân viên", usrMsg);

        // INFO vẫn chạy bình thường
        Assert.Equal("INFO", (await svc.ResolveCommandAsync(device.Id, DeviceCommandTypes.GetDeviceInfo)).Command);
    }
}

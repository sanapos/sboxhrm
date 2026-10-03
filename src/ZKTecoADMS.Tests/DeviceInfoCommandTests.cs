using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;
using ZKTecoADMS.Application.Commands.DeviceCommands.CreateDeviceCmd;
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
        Assert.True(info.PreferStampSync);
        Assert.False(info.SupportsEnrollFingerprint);
        Assert.False(info.SupportsDoorControl);
        Assert.True(AdmsEngineProfiles.UsesCheckStampSync(info.EngineProfile));
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
    public async Task Lx35_sync_queues_stamp_marker_plus_check_and_blocks_unsupported_commands()
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
        var tenant = new NoTenant();
        var devices = new EfRepository<Device>(db, NullLogger<EfRepository<Device>>.Instance, tenant);
        var svc = new DeviceCapabilityService(
            devices,
            new EfRepository<DeviceInfo>(db, NullLogger<EfRepository<DeviceInfo>>.Instance, tenant),
            NullLogger<DeviceCapabilityService>.Instance);
        var handler = new CreateDeviceCmdHandler(
            devices,
            new EfRepository<DeviceCommand>(db, NullLogger<EfRepository<DeviceCommand>>.Instance, tenant),
            svc,
            NullLogger<CreateDeviceCmdHandler>.Instance,
            new EfRepository<DeviceUser>(db, NullLogger<EfRepository<DeviceUser>>.Instance, tenant));

        // Máy thật trả -1002 cho DATA QUERY — nhóm máy vẫn giữ PushLite
        await svc.LearnFromCommandResultAsync(device.Id, DeviceCommandTypes.SyncDeviceUsers, -1002, "DATA");
        Assert.Equal(AdmsEngineProfiles.PushLite, (await db.DeviceInfos.AsNoTracking().SingleAsync()).EngineProfile);

        // Nút «Tải chấm công» (app gửi sẵn DATA QUERY ATTLOG có khoảng ngày) → đánh dấu Stamp + CHECK
        var explicitCmd = ClockCommandBuilder.BuildGetAttendanceCommand(new DateTime(2021, 1, 1), new DateTime(2026, 10, 3, 23, 59, 59));
        var att = await handler.Handle(new CreateDeviceCmdCommand(device.Id, (int)DeviceCommandTypes.SyncAttendances, 10, explicitCmd), default);
        Assert.True(att.IsSuccess);
        var cmds = await db.DeviceCommands.AsNoTracking().OrderBy(c => c.CreatedAt).ToListAsync();
        Assert.Contains(cmds, c => c.CommandType == DeviceCommandTypes.SyncAttendances && AdmsEngineProfiles.IsStampSyncMarker(c.Command));
        var check = Assert.Single(cmds, c => c.Command == "CHECK");
        Assert.Equal(DeviceCommandTypes.GetDeviceInfo, check.CommandType);
        // CHECK phải giao xuống máy, đánh dấu thì không
        Assert.False(AdmsEngineProfiles.ShouldSkipDeviceDelivery(check.CommandType, check.Command));

        // Tải user cũng vậy
        await handler.Handle(new CreateDeviceCmdCommand(device.Id, (int)DeviceCommandTypes.SyncDeviceUsers, 10), default);
        Assert.Equal(2, await db.DeviceCommands.CountAsync(c => c.Command == "CHECK"));

        // Lệnh firmware không có: báo rõ, không tạo lệnh
        var enroll = await handler.Handle(new CreateDeviceCmdCommand(device.Id, (int)DeviceCommandTypes.EnrollFingerprint, 10, null, "968315", 9), default);
        Assert.False(enroll.IsSuccess);
        Assert.Contains("trực tiếp trên máy", enroll.Message);
        Assert.False((await handler.Handle(new CreateDeviceCmdCommand(device.Id, (int)DeviceCommandTypes.OpenDoor, 10), default)).IsSuccess);
        // «Xóa toàn bộ user»: CLEAR ALL USERINFO trả -1002 (thử thật) → xóa từng người bằng DATA DELETE USERINFO
        var none = await handler.Handle(new CreateDeviceCmdCommand(device.Id, (int)DeviceCommandTypes.ClearDeviceUsers, 10), default);
        Assert.False(none.IsSuccess); // chưa có danh sách nhân viên → bảo Tải user trước
        db.AddRange(
            new DeviceUser { Id = Guid.NewGuid(), DeviceId = device.Id, Pin = "968315", Name = "Le Van Tho" },
            new DeviceUser { Id = Guid.NewGuid(), DeviceId = device.Id, Pin = "868", Name = "868" });
        await db.SaveChangesAsync();
        var clearUsers = await handler.Handle(new CreateDeviceCmdCommand(device.Id, (int)DeviceCommandTypes.ClearDeviceUsers, 10), default);
        Assert.True(clearUsers.IsSuccess);
        var deletes = await db.DeviceCommands.AsNoTracking().Where(c => c.CommandType == DeviceCommandTypes.DeleteDeviceUser).ToListAsync();
        Assert.Equal(2, deletes.Count);
        Assert.Contains(deletes, c => c.Command == "DATA DELETE USERINFO PIN=968315");
        Assert.All(deletes, c => Assert.NotEqual(Guid.Empty, c.ObjectReferenceId));
        Assert.DoesNotContain(await db.DeviceCommands.AsNoTracking().ToListAsync(), c => c.Command.Contains("CLEAR ALL USERINFO"));
        // CLEAR DATA vẫn gửi bình thường (máy nhận, xóa hết)
        Assert.Equal("CLEAR DATA", (await svc.ResolveCommandAsync(device.Id, DeviceCommandTypes.ClearData)).Command);
        var cap = await svc.GetCapabilityDtoAsync(device.Id);
        Assert.False(cap.AllowEnrollFingerprintUi);
        Assert.False(cap.AllowDoorControlUi);
        Assert.False(cap.AllowEnrollFaceUi);
        Assert.Equal(6, await db.DeviceCommands.CountAsync()); // 2 đánh dấu + 2 CHECK + 2 xóa NV

        // INFO vẫn chạy bình thường
        Assert.Equal("INFO", (await svc.ResolveCommandAsync(device.Id, DeviceCommandTypes.GetDeviceInfo)).Command);
    }

    [Fact]
    public void Handshake_for_lx35_sends_digit_trans_flag_only()
    {
        var lx = PushDeviceConfigBuilder.BuildGetOptionResponse("1313254900299", "0", digitTransFlagOnly: true);
        Assert.Contains("TransFlag=1111111111", lx);
        Assert.DoesNotContain("TransFlag=AttLog", lx);
        Assert.Contains("ATTLOGStamp=0", lx);
        var other = PushDeviceConfigBuilder.BuildGetOptionResponse("0004521206093", "9999");
        Assert.Contains("TransFlag=AttLog", other); // máy khác giữ nguyên
    }
}

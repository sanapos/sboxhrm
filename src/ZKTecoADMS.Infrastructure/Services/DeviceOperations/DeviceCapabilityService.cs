using Microsoft.Extensions.Logging;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Domain.Repositories;
namespace ZKTecoADMS.Infrastructure.Services.DeviceOperations;

public class DeviceCapabilityService(
    IRepository<Device> deviceRepository,
    IRepository<DeviceInfo> deviceInfoRepository,
    ILogger<DeviceCapabilityService> logger) : IDeviceCapabilityService
{
    public async Task<DeviceInfo> EnsureProfileAsync(Guid deviceId, CancellationToken cancellationToken = default)
    {
        var device = await deviceRepository.GetByIdAsync(deviceId, cancellationToken: cancellationToken)
            ?? throw new KeyNotFoundException($"Device {deviceId} not found");

        var info = await deviceInfoRepository.GetSingleAsync(di => di.DeviceId == deviceId, cancellationToken: cancellationToken)
            ?? new DeviceInfo { DeviceId = deviceId };

        if (string.IsNullOrWhiteSpace(info.EngineProfile) || info.EngineProfile == AdmsEngineProfiles.Default)
        {
            var profile = AdmsEngineProfiles.ResolveProfile(info.Platform, info.FirmwareVersion, device.SerialNumber, info.PushVersion);
            AdmsEngineProfiles.ApplyProfileDefaults(info, profile);
            await deviceInfoRepository.AddOrUpdateAsync(info);
            logger.LogInformation(
                "[Capability] Assigned profile {Profile} for SN={SN} Platform={Platform} FW={FW}",
                profile, device.SerialNumber, info.Platform, info.FirmwareVersion);
        }
        else
        {
            // Sửa PullDeny gắn nhầm (SN 131* + ZLM60/8300) → profile đúng.
            var resolved = AdmsEngineProfiles.ResolveProfile(info.Platform, info.FirmwareVersion, device.SerialNumber, info.PushVersion);
            if (string.Equals(info.EngineProfile, AdmsEngineProfiles.PullDeny, StringComparison.OrdinalIgnoreCase)
                && !string.Equals(resolved, AdmsEngineProfiles.PullDeny, StringComparison.OrdinalIgnoreCase))
            {
                AdmsEngineProfiles.ApplyProfileDefaults(info, resolved);
                await deviceInfoRepository.AddOrUpdateAsync(info);
                logger.LogInformation(
                    "[Capability] Corrected PullDeny→{Profile} for SN={SN} Platform={Platform} FW={FW}",
                    resolved, device.SerialNumber, info.Platform, info.FirmwareVersion);
            }
        }

        return info;
    }

    public async Task ApplyIdentityFromOptionsAsync(
        Guid deviceId,
        string? platform,
        string? firmware,
        string? pushVersion,
        string? deviceModelName,
        string? oemVendor,
        CancellationToken cancellationToken = default)
    {
        var device = await deviceRepository.GetByIdAsync(deviceId, cancellationToken: cancellationToken);
        if (device == null) return;

        var info = await deviceInfoRepository.GetSingleAsync(di => di.DeviceId == deviceId, cancellationToken: cancellationToken)
            ?? new DeviceInfo { DeviceId = deviceId };

        if (!string.IsNullOrWhiteSpace(platform))
            info.Platform = platform;
        if (!string.IsNullOrWhiteSpace(firmware))
            info.FirmwareVersion = firmware;
        if (!string.IsNullOrWhiteSpace(pushVersion))
            info.PushVersion = pushVersion;
        if (!string.IsNullOrWhiteSpace(deviceModelName))
            info.DeviceModelName = deviceModelName;
        if (!string.IsNullOrWhiteSpace(oemVendor))
            info.OemVendor = oemVendor;

        // Keep DevSupportData as free-form dump for diagnostics
        if (!string.IsNullOrWhiteSpace(platform) && string.IsNullOrWhiteSpace(info.DevSupportData))
            info.DevSupportData = platform;

        var profile = AdmsEngineProfiles.ResolveProfile(info.Platform, info.FirmwareVersion, device.SerialNumber, info.PushVersion);
        // Do not overwrite a learned PullDeny with Default when SN pattern still says PullDeny.
        // Nhưng phải sửa PullDeny gắn nhầm (SN 131* + ZLM60/Ver6 → TftLegacy).
        if (string.IsNullOrWhiteSpace(info.EngineProfile)
            || info.EngineProfile == AdmsEngineProfiles.Default
            || profile == AdmsEngineProfiles.PullDeny
            || (string.Equals(info.EngineProfile, AdmsEngineProfiles.PullDeny, StringComparison.OrdinalIgnoreCase)
                && profile != AdmsEngineProfiles.PullDeny))
        {
            AdmsEngineProfiles.ApplyProfileDefaults(info, profile);
        }

        await deviceInfoRepository.AddOrUpdateAsync(info);
    }

    public async Task LearnFromCommandResultAsync(
        Guid deviceId,
        DeviceCommandTypes commandType,
        int returnCode,
        string? commandText,
        CancellationToken cancellationToken = default)
    {
        var info = await deviceInfoRepository.GetSingleAsync(di => di.DeviceId == deviceId, cancellationToken: cancellationToken);
        if (info == null) return;

        var changed = false;
        var note = $"[{DateTime.UtcNow:yyyy-MM-dd HH:mm}] {commandType} Return={returnCode}";

        // Stamp-sync marker (server-only) is not a query/enroll capability signal.
        var isStampCheck = AdmsEngineProfiles.IsStampSyncMarker(commandText)
            || string.Equals(commandText?.Trim(), "CHECK", StringComparison.OrdinalIgnoreCase);

        if (returnCode == -1002 || returnCode == -22 || returnCode == -1004)
        {
            if (isStampCheck) return;

            switch (commandType)
            {
                case DeviceCommandTypes.SyncDeviceUsers:
                    if (info.SupportsUserQuery != false)
                    {
                        // Chỉ đánh dấu USERINFO query fail — không khóa ATTLOG query
                        // (nhiều máy PullDeny USERINFO vẫn hỗ trợ DATA QUERY ATTLOG).
                        info.SupportsUserQuery = false;
                        // LX35 (PushLite) cũng từ chối USERINFO nhưng vẫn tải ATTLOG với ngày dạng có dấu cách —
                        // giữ nhóm đã nhận theo Platform, đổi sang PullDeny sẽ gửi lại ngày dạng «T» → -1002.
                        if (!string.Equals(info.EngineProfile, AdmsEngineProfiles.PushLite, StringComparison.OrdinalIgnoreCase))
                            info.EngineProfile = AdmsEngineProfiles.PullDeny;
                        changed = true;
                    }
                    break;
                case DeviceCommandTypes.SyncAttendances:
                    if (info.SupportsAttendanceQuery != false)
                    {
                        info.SupportsAttendanceQuery = false;
                        changed = true;
                    }
                    break;
                case DeviceCommandTypes.EnrollFingerprint:
                case DeviceCommandTypes.EnrollFace:
                    if (info.SupportsEnrollFingerprint != false)
                    {
                        info.SupportsEnrollFingerprint = false;
                        changed = true;
                    }
                    break;
                case DeviceCommandTypes.OpenDoor:
                case DeviceCommandTypes.CloseDoor:
                    if (info.SupportsDoorControl != false)
                    {
                        info.SupportsDoorControl = false;
                        changed = true;
                    }
                    break;
                case DeviceCommandTypes.SyncFingerprints:
                case DeviceCommandTypes.SyncFaces:
                    break;
            }
        }
        else if (returnCode == 0)
        {
            switch (commandType)
            {
                case DeviceCommandTypes.SyncDeviceUsers
                    when !isStampCheck && (LooksLikeQuery(commandText, "USERINFO") || IsDataAck(commandText)):
                    if (info.SupportsUserQuery != true)
                    {
                        info.SupportsUserQuery = true;
                        changed = true;
                    }
                    break;
                case DeviceCommandTypes.SyncAttendances
                    when !isStampCheck && (LooksLikeQuery(commandText, "ATTLOG") || IsDataAck(commandText)):
                    if (info.SupportsAttendanceQuery != true)
                    {
                        info.SupportsAttendanceQuery = true;
                        changed = true;
                    }
                    break;
                case DeviceCommandTypes.EnrollFingerprint when !isStampCheck:
                    if (info.SupportsEnrollFingerprint != true)
                    {
                        info.SupportsEnrollFingerprint = true;
                        changed = true;
                    }
                    break;
                case DeviceCommandTypes.OpenDoor:
                case DeviceCommandTypes.CloseDoor:
                    if (info.SupportsDoorControl != true)
                    {
                        info.SupportsDoorControl = true;
                        changed = true;
                    }
                    break;
            }
        }

        if (!changed) return;

        info.CapabilityUpdatedAt = DateTime.UtcNow;
        info.CapabilityNotes = AppendNote(info.CapabilityNotes, note);
        await deviceInfoRepository.UpdateAsync(info, cancellationToken);
        logger.LogWarning(
            "[Capability] Learned for DeviceId={DeviceId}: UserQuery={UQ} AttQuery={AQ} EnrollFP={EF} Door={Door} PreferStamp={PS} Profile={Profile}",
            deviceId, info.SupportsUserQuery, info.SupportsAttendanceQuery,
            info.SupportsEnrollFingerprint, info.SupportsDoorControl, info.PreferStampSync, info.EngineProfile);
    }

    public async Task<(string Command, string? Warning)> ResolveCommandAsync(
        Guid deviceId,
        DeviceCommandTypes commandType,
        string? pin = null,
        int? fingerIndex = null,
        string? explicitCommand = null,
        DateTime? attStart = null,
        DateTime? attEnd = null,
        CancellationToken cancellationToken = default)
    {
        var info = await EnsureProfileAsync(deviceId, cancellationToken);

        if (AdmsEngineProfiles.UsesCheckStampSync(info.EngineProfile))
        {
            // LX35: DATA QUERY luôn -1002; CHECK + Stamp=0 tải lại được (đã thử thật). CreateDeviceCmd gửi kèm CHECK.
            switch (commandType)
            {
                case DeviceCommandTypes.SyncAttendances:
                case DeviceCommandTypes.SyncDeviceUsers:
                    return (AdmsEngineProfiles.StampSyncCommand, null);
                case DeviceCommandTypes.SyncFingerprints:
                    return (string.Empty, PushLiteNoFingerprintSync);
                case DeviceCommandTypes.EnrollFingerprint:
                    return (string.Empty, PushLiteNoRemoteEnroll);
                case DeviceCommandTypes.EnrollFace:
                    return (string.Empty, "Máy này (dòng LX35) không có nhận diện khuôn mặt.");
                case DeviceCommandTypes.OpenDoor:
                case DeviceCommandTypes.CloseDoor:
                    return (string.Empty, "Máy này (dòng LX35) không có lệnh mở / đóng cửa từ xa.");
            }
        }

        if (!string.IsNullOrWhiteSpace(explicitCommand))
        {
            // Máy đã từ chối DATA QUERY ATTLOG — không gửi lại lệnh chắc chắn lỗi.
            if (commandType == DeviceCommandTypes.SyncAttendances && info.SupportsAttendanceQuery == false
                && ClockCommandBuilder.TryParseAttendanceQuery(explicitCommand, out _, out _))
            {
                return (AdmsEngineProfiles.StampSyncCommand,
                    "Máy không hỗ trợ DATA QUERY ATTLOG. Server dùng ATTLOGStamp=0 + realtime; log đã chấm vẫn tự đẩy lên.");
            }

            // Nút «Tải chấm công» dựng sẵn lệnh có chữ T — đổi định dạng theo máy.
            if (commandType == DeviceCommandTypes.SyncAttendances
                && ClockCommandBuilder.TryParseAttendanceQuery(explicitCommand, out var s, out var e))
            {
                return (ClockCommandBuilder.BuildGetAttendanceCommand(
                    s, e, AdmsEngineProfiles.UsesSpaceDateTime(info.EngineProfile)), null);
            }
            return (explicitCommand, null);
        }

        // Lỗi học được trên lệnh tải user / chấm công không khóa vĩnh viễn: sau 7 ngày thử lại một lần.
        if (commandType is DeviceCommandTypes.SyncDeviceUsers or DeviceCommandTypes.SyncAttendances
            && (info.SupportsUserQuery == false || info.SupportsAttendanceQuery == false)
            && info.CapabilityUpdatedAt.HasValue
            && info.CapabilityUpdatedAt.Value < DateTime.UtcNow.AddDays(-7))
        {
            if (commandType == DeviceCommandTypes.SyncDeviceUsers && info.SupportsUserQuery == false)
                info.SupportsUserQuery = null;
            if (commandType == DeviceCommandTypes.SyncAttendances && info.SupportsAttendanceQuery == false)
                info.SupportsAttendanceQuery = null;
            info.CapabilityUpdatedAt = DateTime.UtcNow;
            info.CapabilityNotes = AppendNote(info.CapabilityNotes, $"[{DateTime.UtcNow:yyyy-MM-dd HH:mm}] retry {commandType} after 7 days");
            await deviceInfoRepository.UpdateAsync(info, cancellationToken);
        }

        switch (commandType)
        {
            case DeviceCommandTypes.EnrollFingerprint:
                if (info.SupportsEnrollFingerprint == false)
                {
                    return (string.Empty,
                        "Máy không hỗ trợ đăng ký vân tay từ xa (ENROLL_FP). Hãy đăng ký trực tiếp trên máy.");
                }

                if (string.IsNullOrWhiteSpace(pin))
                    return ("NOT IMPLEMENTED", null);
                return (ClockCommandBuilder.BuildEnrollFingerprintCommand(pin, fingerIndex ?? 0), null);

            case DeviceCommandTypes.DeleteFingerprint:
                if (string.IsNullOrWhiteSpace(pin))
                    return ("NOT IMPLEMENTED", null);
                return (ClockCommandBuilder.BuildDeleteFingerprintCommand(pin, fingerIndex ?? -1), null);

            case DeviceCommandTypes.EnrollFace:
                if (info.SupportsFaceUpdate == false)
                {
                    return (string.Empty,
                        "Máy không hỗ trợ đăng ký khuôn mặt từ xa. Hãy đăng ký trực tiếp trên máy.");
                }

                if (string.IsNullOrWhiteSpace(pin))
                    return ("NOT IMPLEMENTED", null);
                return (ClockCommandBuilder.BuildEnrollFaceCommand(pin), null);

            case DeviceCommandTypes.DeleteFace:
                if (string.IsNullOrWhiteSpace(pin))
                    return ("NOT IMPLEMENTED", null);
                return (ClockCommandBuilder.BuildDeleteFaceCommand(pin), null);

            case DeviceCommandTypes.SyncDeviceUsers:
                if (info.SupportsUserQuery == false)
                {
                    return (AdmsEngineProfiles.StampSyncCommand,
                        "Máy không hỗ trợ DATA QUERY USERINFO. Server sẽ dùng Stamp/realtime; tải NV xuống máy bằng DATA UPDATE.");
                }

                return (ClockCommandBuilder.BuildGetAllUsersCommand(), null);

            case DeviceCommandTypes.SyncAttendances:
                // Chỉ stamp khi ATTLOG query đã fail thật — không dùng PreferStampSync
                // (flag đó từng bị set chung khi USERINFO -1002 → chặn nhầm tải công).
                if (info.SupportsAttendanceQuery == false)
                {
                    return (AdmsEngineProfiles.StampSyncCommand,
                        "Máy không hỗ trợ DATA QUERY ATTLOG. Server dùng ATTLOGStamp=0 + realtime; log đã chấm vẫn tự đẩy lên.");
                }

                return (ClockCommandBuilder.BuildGetAttendanceCommand(
                    attStart, attEnd, AdmsEngineProfiles.UsesSpaceDateTime(info.EngineProfile)), null);

            case DeviceCommandTypes.SyncFingerprints:
                return (ClockCommandBuilder.BuildGetFingerprintsCommand(), null);

            case DeviceCommandTypes.ClearAttendances:
                return ("CLEAR LOG", null);
            case DeviceCommandTypes.ClearDeviceUsers:
                return ("CLEAR ALL USERINFO", null);
            case DeviceCommandTypes.ClearData:
                return ("CLEAR DATA", null);
            case DeviceCommandTypes.RestartDevice:
                return ("REBOOT", null);
            case DeviceCommandTypes.GetDeviceInfo:
                return ("INFO", null);

            case DeviceCommandTypes.OpenDoor:
                if (info.SupportsDoorControl == false)
                {
                    return (string.Empty,
                        "Máy không hỗ trợ mở cửa từ xa. Chỉ máy có relay/khóa cửa mới dùng được.");
                }
                // agap.top / SenseFace 2A: C:OPENDORn:AC_UNLOCK (ACK Return=0 + mở khóa thật).
                return (ClockCommandBuilder.BuildOpenDoorCommand(useAccessControlProtocol: false), null);

            case DeviceCommandTypes.CloseDoor:
                if (info.SupportsDoorControl == false)
                {
                    return (string.Empty,
                        "Máy không hỗ trợ đóng cửa từ xa. Chỉ máy có relay/khóa cửa mới dùng được.");
                }
                return (ClockCommandBuilder.BuildCloseDoorCommand(), null);

            default:
                return ("NOT IMPLEMENTED", null);
        }
    }

    // Đã thử trên LX35 thật (SN 1313254900299, FW ZLM31-FXO1-3.1.8, Push 3.0.1) + ROM: không có ENROLL_FP;
    // BIODATAStamp=0 + CHECK không làm máy gửi mẫu vân tay.
    internal const string PushLiteNoRemoteEnroll =
        "Máy này (dòng LX35) không hỗ trợ đăng ký vân tay từ xa. Đăng ký vân tay trực tiếp trên máy "
        + "(Menu → Quản lý người dùng → chọn nhân viên → Vân tay).";

    internal const string PushLiteNoFingerprintSync =
        "Máy này (dòng LX35) chưa gửi được mẫu vân tay về Sbox. Nhân viên đăng ký vân tay trực tiếp trên từng máy.";

    public async Task<DeviceCapabilityDto> GetCapabilityDtoAsync(Guid deviceId, CancellationToken cancellationToken = default)
    {
        var info = await EnsureProfileAsync(deviceId, cancellationToken);
        var profile = info.EngineProfile ?? AdmsEngineProfiles.Default;
        var allowUserSync = info.SupportsUserQuery != false; // unknown = allow probe once
        var allowAttSync = info.SupportsAttendanceQuery != false;
        // LX35: ROM không có ENROLL_FP / AC_UNLOCK, máy không camera — ẩn nút kể cả máy đã xếp nhóm trước bản này.
        var pushLite = AdmsEngineProfiles.UsesCheckStampSync(profile);
        var allowEnroll = !pushLite && info.SupportsEnrollFingerprint != false;
        var allowFace = !pushLite && info.SupportsFaceUpdate == true;
        var allowDoor = !pushLite && info.SupportsDoorControl != false;

        // UI: still show sync when PreferStampSync, but with different meaning (stamp/realtime)
        return new DeviceCapabilityDto(
            EngineProfile: profile,
            Platform: info.Platform,
            FirmwareVersion: info.FirmwareVersion,
            PushVersion: info.PushVersion,
            DeviceModelName: info.DeviceModelName,
            SupportsUserQuery: info.SupportsUserQuery,
            SupportsAttendanceQuery: info.SupportsAttendanceQuery,
            SupportsEnrollFingerprint: info.SupportsEnrollFingerprint,
            SupportsFaceUpdate: info.SupportsFaceUpdate,
            SupportsDoorControl: info.SupportsDoorControl,
            PreferStampSync: info.PreferStampSync,
            AllowSyncUsersUi: true,
            AllowSyncAttendancesUi: true,
            AllowEnrollFingerprintUi: allowEnroll,
            AllowEnrollFaceUi: allowFace,
            AllowDoorControlUi: allowDoor,
            Notes: pushLite
                ? "Dòng LX35: tải chấm công / user bằng CHECK (máy gửi lại toàn bộ); thêm nhân viên từ Sbox xuống máy được; "
                  + "vân tay đăng ký trực tiếp trên máy."
                : info.CapabilityNotes
                ?? (info.PreferStampSync
                    ? "Máy kiểu pull-deny: đẩy NV xuống + chấm realtime; không QUERY/ENROLL từ xa."
                    : null));
    }

    /// <summary>Firmware ZK chỉ trả «CMD=DATA» cho mọi lệnh DATA UPDATE/QUERY/DELETE.</summary>
    private static bool IsDataAck(string? command) =>
        string.Equals(command?.Trim(), "DATA", StringComparison.OrdinalIgnoreCase);

    private static bool LooksLikeQuery(string? command, string table) =>
        !string.IsNullOrWhiteSpace(command)
        && command.Contains("QUERY", StringComparison.OrdinalIgnoreCase)
        && command.Contains(table, StringComparison.OrdinalIgnoreCase);

    private static string AppendNote(string? existing, string note)
    {
        if (string.IsNullOrWhiteSpace(existing)) return note.Length <= 1000 ? note : note[..1000];
        var merged = existing + " | " + note;
        return merged.Length <= 1000 ? merged : merged[^1000..];
    }
}

using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Interfaces;

public interface IDeviceCapabilityService
{
    Task<DeviceInfo> EnsureProfileAsync(Guid deviceId, CancellationToken cancellationToken = default);

    Task ApplyIdentityFromOptionsAsync(
        Guid deviceId,
        string? platform,
        string? firmware,
        string? pushVersion,
        string? deviceModelName,
        string? oemVendor,
        CancellationToken cancellationToken = default);

    Task LearnFromCommandResultAsync(
        Guid deviceId,
        DeviceCommandTypes commandType,
        int returnCode,
        string? commandText,
        CancellationToken cancellationToken = default);

    /// <summary>Build ADMS command string for a device (capability-aware).</summary>
    Task<(string Command, string? Warning)> ResolveCommandAsync(
        Guid deviceId,
        DeviceCommandTypes commandType,
        string? pin = null,
        int? fingerIndex = null,
        string? explicitCommand = null,
        DateTime? attStart = null,
        DateTime? attEnd = null,
        CancellationToken cancellationToken = default);

    Task<DeviceCapabilityDto> GetCapabilityDtoAsync(Guid deviceId, CancellationToken cancellationToken = default);
}

public record DeviceCapabilityDto(
    string EngineProfile,
    string? Platform,
    string? FirmwareVersion,
    string? PushVersion,
    string? DeviceModelName,
    bool? SupportsUserQuery,
    bool? SupportsAttendanceQuery,
    bool? SupportsEnrollFingerprint,
    bool? SupportsFaceUpdate,
    bool? SupportsDoorControl,
    bool PreferStampSync,
    bool AllowSyncUsersUi,
    bool AllowSyncAttendancesUi,
    bool AllowEnrollFingerprintUi,
    bool AllowEnrollFaceUi,
    bool AllowDoorControlUi,
    string? Notes);

namespace ZKTecoADMS.Application.DTOs.Devices;

public record DeviceInfoDto(
    string DeviceId,
    string? FirmwareVersion,
    int EnrolledUserCount,
    int FingerprintCount,
    int AttendanceCount,
    string? DeviceIp,
    string? FingerprintVersion,
    string? FaceVersion,
    string? FaceTemplateCount,
    string? DevSupportData,
    string? Platform = null,
    string? PushVersion = null,
    string? DeviceModelName = null,
    string? OemVendor = null,
    string? EngineProfile = null,
    bool? SupportsUserQuery = null,
    bool? SupportsAttendanceQuery = null,
    bool? SupportsEnrollFingerprint = null,
    bool? SupportsFaceUpdate = null,
    bool? SupportsDoorControl = null,
    bool PreferStampSync = false,
    string? CapabilityNotes = null
);

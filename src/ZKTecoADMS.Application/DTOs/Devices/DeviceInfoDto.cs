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
    string? DevSupportData
);
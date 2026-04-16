using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.DTOs.Attendances;

public record AttendanceDto(
    Guid Id,
    DateTime AttendanceTime,
    string DeviceName,
    string Pin,
    string? EmployeeCode,
    string UserName,
    string? DeviceUserName,
    int Privilege,
    VerifyModes VerifyMode,
    AttendanceStates AttendanceState,
    string? WorkCode,
    string? Note = null
);
using System.Text.Json.Serialization;
using ZKTecoADMS.Application.Serialization;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.DTOs.Attendances;

public record AttendanceDto(
    Guid Id,
    [property: JsonConverter(typeof(VnWallClockDateTimeJsonConverter))] DateTime AttendanceTime,
    string DeviceName,
    string Pin,
    string? EmployeeCode,
    string UserName,
    string? DeviceUserName,
    int Privilege,
    VerifyModes VerifyMode,
    AttendanceStates AttendanceState,
    string? WorkCode,
    string? Note = null,
    Guid? MobileAttendanceRecordId = null,
    double? Latitude = null,
    double? Longitude = null,
    string? LocationName = null,
    string? SitePhotoUrl = null
);
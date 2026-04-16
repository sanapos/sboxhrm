using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.DTOs.Attendances;

public class MonthlyAttendanceSummaryDto
{
    public List<DailyAttendanceDto> DailyRecords { get; set; } = new();
    public int Year { get; set; }
    public int Month { get; set; }
    public string EmployeeName { get; set; } = string.Empty;
    public Guid EmployeeId { get; set; }
}

public class DailyAttendanceDto
{
    public DateTime Date { get; set; }
    public List<AttendanceRecordDto> Attendances { get; set; } = new();
    public ShiftInfoDto? Shift { get; set; }
    public LeaveInfoDto? Leave { get; set; }
    public bool HasShift { get; set; }
    public bool IsLeave { get; set; }
}

public class AttendanceRecordDto
{
    public Guid Id { get; set; }
    public DateTime CheckInTime { get; set; }
    public DateTime? CheckOutTime { get; set; }
    public string DeviceName { get; set; } = string.Empty;
    public VerifyModes VerifyMode { get; set; }
    public AttendanceStates AttendanceState { get; set; }
}

public class ShiftInfoDto
{
    public Guid Id { get; set; }
    public DateTime StartTime { get; set; }
    public DateTime EndTime { get; set; }
    public string? Description { get; set; }
    public ShiftStatus Status { get; set; }
}

public class LeaveInfoDto
{
    public Guid Id { get; set; }
    public LeaveType Type { get; set; }
    public string Reason { get; set; } = string.Empty;
    public LeaveStatus Status { get; set; }
    public bool IsHalfShift { get; set; }
}

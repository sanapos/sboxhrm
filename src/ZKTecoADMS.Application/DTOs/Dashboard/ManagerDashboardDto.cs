namespace ZKTecoADMS.Application.DTOs.Dashboard;

public class ManagerDashboardDto
{
    public List<EmployeeOnLeaveDto> EmployeesOnLeave { get; set; } = new();
    public List<AbsentDeviceUserDto> AbsentEmployees { get; set; } = new();
    public List<LateDeviceUserDto> LateEmployees { get; set; } = new();
    public List<TodayDeviceUserDto> TodayEmployees { get; set; } = new();
    public AttendanceRateDto AttendanceRate { get; set; } = null!;
}

public class EmployeeOnLeaveDto
{
    public Guid EmployeeUserId { get; set; }
    public string FullName { get; set; } = string.Empty;
    public string Email { get; set; } = string.Empty;
    public Guid LeaveId { get; set; }
    public string LeaveType { get; set; } = string.Empty;
    public DateTime LeaveStartDate { get; set; }
    public DateTime LeaveEndDate { get; set; }
    public bool IsFullDay { get; set; }
    public string Reason { get; set; } = string.Empty;
    public Guid ShiftId { get; set; }
    public DateTime ShiftStartTime { get; set; }
    public DateTime ShiftEndTime { get; set; }
}

public class AbsentDeviceUserDto
{
    public Guid EmployeeUserId { get; set; }
    public string FullName { get; set; } = string.Empty;
    public string Email { get; set; } = string.Empty;
    public Guid ShiftId { get; set; }
    public DateTime ShiftStartTime { get; set; }
    public DateTime ShiftEndTime { get; set; }
    public string Department { get; set; } = string.Empty;
}

public class LateDeviceUserDto
{
    public Guid EmployeeUserId { get; set; }
    public string FullName { get; set; } = string.Empty;
    public string Email { get; set; } = string.Empty;
    public Guid ShiftId { get; set; }
    public DateTime ShiftStartTime { get; set; }
    public DateTime? ActualCheckInTime { get; set; }
    public TimeSpan LateBy { get; set; }
    public string Department { get; set; } = string.Empty;
}

public class TodayDeviceUserDto
{
    public Guid EmployeeUserId { get; set; }
    public string FullName { get; set; } = string.Empty;
    public string Email { get; set; } = string.Empty;
    public Guid? ShiftId { get; set; }
    public DateTime? ShiftStartTime { get; set; }
    public DateTime? ShiftEndTime { get; set; }
    public string Status { get; set; } = string.Empty; // "On Leave", "Present", "Late", "Absent", "No Shift"
    public DateTime? CheckInTime { get; set; }
    public DateTime? CheckOutTime { get; set; }
    public string Department { get; set; } = string.Empty;
}

public class AttendanceRateDto
{
    public int TotalEmployeesWithShift { get; set; }
    public int PresentEmployees { get; set; }
    public int LateEmployees { get; set; }
    public int AbsentEmployees { get; set; }
    public int OnLeaveEmployees { get; set; }
    public double AttendancePercentage { get; set; }
    public double PunctualityPercentage { get; set; }
}

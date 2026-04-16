namespace ZKTecoADMS.Application.DTOs.Dashboard;

public class ShiftInfoDto
{
    public Guid Id { get; set; }
    public DateTime StartTime { get; set; }
    public DateTime EndTime { get; set; }
    public string? Description { get; set; }
    public int Status { get; set; }
    public double TotalHours => (EndTime - StartTime).TotalHours;
    public bool IsToday => StartTime.Date == DateTime.Now.Date;
}

public class AttendanceInfoDto
{
    public Guid Id { get; set; }
    public DateTime? CheckInTime { get; set; }
    public DateTime? CheckOutTime { get; set; }
    public double WorkHours => CheckInTime == null ? 0 : (CheckOutTime == null ? (DateTime.Now - CheckInTime.Value).TotalHours : (CheckOutTime.Value - CheckInTime.Value).TotalHours);
    public string Status { get; set; } = "not-started"; // checked-in, checked-out, not-started
    public bool IsLate { get; set; }
    public bool IsEarlyOut { get; set; }
    public int? LateMinutes { get; set; }
    public int? EarlyOutMinutes { get; set; }
}

public class AttendanceStatsDto
{
    public int TotalWorkDays { get; set; }
    public int PresentDays { get; set; }
    public int AbsentDays { get; set; }
    public int LateCheckIns { get; set; }
    public int EarlyCheckOuts { get; set; }
    public double AttendanceRate { get; set; }
    public double PunctualityRate { get; set; }
    public string AverageWorkHours { get; set; } = "0.0";
    public string Period { get; set; } = "month"; // week, month, year
}

public class EmployeeDashboardDto
{
    public ShiftInfoDto? TodayShift { get; set; }
    public ShiftInfoDto? NextShift { get; set; }
    public AttendanceInfoDto? CurrentAttendance { get; set; }
    public AttendanceStatsDto AttendanceStats { get; set; } = new();
}

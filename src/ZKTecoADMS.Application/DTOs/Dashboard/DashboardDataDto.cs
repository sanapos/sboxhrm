namespace ZKTecoADMS.Application.DTOs.Dashboard;

public class DashboardDataDto
{
    public DashboardSummaryDto Summary { get; set; } = null!;
    public List<EmployeePerformanceDto> TopPerformers { get; set; } = new();
    public List<EmployeePerformanceDto> LateEmployees { get; set; } = new();
    public List<DepartmentStatisticsDto> DepartmentStats { get; set; } = new();
    public List<AttendanceTrendDto> AttendanceTrends { get; set; } = new();
    public List<DeviceStatusDto> DeviceStatuses { get; set; } = new();
}

public class DashboardSummaryDto
{
    public int TotalEmployees { get; set; }
    public int ActiveEmployees { get; set; }
    public int InactiveEmployees { get; set; }
    public int TotalDevices { get; set; }
    public int OnlineDevices { get; set; }
    public int OfflineDevices { get; set; }
    public int TodayCheckIns { get; set; }
    public int TodayCheckOuts { get; set; }
    public int TodayAbsences { get; set; }
    public int TodayLateArrivals { get; set; }
    public double AverageAttendanceRate { get; set; }
}

public class EmployeePerformanceDto
{
    public Guid UserId { get; set; }
    public string FullName { get; set; } = string.Empty;
    public string Department { get; set; } = string.Empty;
    public int TotalAttendanceDays { get; set; }
    public int OnTimeDays { get; set; }
    public int LateDays { get; set; }
    public int AbsentDays { get; set; }
    public double AttendanceRate { get; set; }
    public double PunctualityRate { get; set; }
    public TimeSpan AverageWorkHours { get; set; }
    public TimeSpan? AverageLateTime { get; set; }
    public DateTime? LastCheckIn { get; set; }
    public DateTime? LastCheckOut { get; set; }
}

public class DepartmentStatisticsDto
{
    public string Department { get; set; } = string.Empty;
    public int TotalEmployees { get; set; }
    public int ActiveToday { get; set; }
    public int AbsentToday { get; set; }
    public int LateToday { get; set; }
    public double AttendanceRate { get; set; }
    public double PunctualityRate { get; set; }
    public TimeSpan AverageWorkHours { get; set; }
}

public class AttendanceTrendDto
{
    public DateTime Date { get; set; }
    public int TotalCheckIns { get; set; }
    public int TotalCheckOuts { get; set; }
    public int LateArrivals { get; set; }
    public int Absences { get; set; }
    public double AttendanceRate { get; set; }
}

public class DeviceStatusDto
{
    public Guid DeviceId { get; set; }
    public string DeviceName { get; set; } = string.Empty;
    public string Location { get; set; } = string.Empty;
    public string Status { get; set; } = string.Empty;
    public DateTime? LastOnline { get; set; }
    public int RegisteredUsers { get; set; }
    public int TodayAttendances { get; set; }
}

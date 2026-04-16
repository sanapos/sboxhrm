namespace ZKTecoADMS.Api.Models.Responses;

public class DashboardResponse
{
    public DashboardSummary Summary { get; set; } = null!;
    public List<EmployeePerformance> TopPerformers { get; set; } = new();
    public List<EmployeePerformance> LateEmployees { get; set; } = new();
    public List<DepartmentStatistics> DepartmentStats { get; set; } = new();
    public List<AttendanceTrend> AttendanceTrends { get; set; } = new();
    public List<DeviceStatus> DeviceStatuses { get; set; } = new();
}

public class DashboardSummary
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

public class EmployeePerformance
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

public class DepartmentStatistics
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

public class AttendanceTrend
{
    public DateTime Date { get; set; }
    public int TotalCheckIns { get; set; }
    public int TotalCheckOuts { get; set; }
    public int LateArrivals { get; set; }
    public int Absences { get; set; }
    public double AttendanceRate { get; set; }
}

public class DeviceStatus
{
    public Guid DeviceId { get; set; }
    public string DeviceName { get; set; } = string.Empty;
    public string Location { get; set; } = string.Empty;
    public string Status { get; set; } = string.Empty;
    public DateTime? LastOnline { get; set; }
    public int RegisteredUsers { get; set; }
    public int TodayAttendances { get; set; }
}

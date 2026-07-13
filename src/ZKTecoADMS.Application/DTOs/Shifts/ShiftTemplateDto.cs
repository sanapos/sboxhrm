namespace ZKTecoADMS.Application.DTOs.Shifts;

public class ShiftTemplateDto
{
    public Guid Id { get; set; }
    public Guid ManagerId { get; set; }
    public string ManagerName { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string? Code { get; set; }
    public TimeSpan StartTime { get; set; }
    public TimeSpan EndTime { get; set; }
    public int MaximumAllowedLateMinutes { get; set; } = 30;
    public int MaximumAllowedEarlyLeaveMinutes { get; set; } = 30;
    public int BreakTimeMinutes { get; set; } = 0;
    public int EarlyCheckInMinutes { get; set; } = 30;
    public int LateGraceMinutes { get; set; } = 5;
    public int EarlyLeaveGraceMinutes { get; set; } = 5;
    public int OvertimeMinutesThreshold { get; set; } = 30;
    public string? ShiftType { get; set; }
    public string? Description { get; set; }
    public bool IsActive { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime? UpdatedAt { get; set; }
    
    public double TotalHours => EndTime >= StartTime
        ? (EndTime - StartTime).TotalHours
        : (TimeSpan.FromHours(24) - StartTime + EndTime).TotalHours;
}

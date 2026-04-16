namespace ZKTecoADMS.Application.DTOs.Shifts;

public class CreateShiftTemplateRequest
{
    public string Name { get; set; } = null!;
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
    public bool IsActive { get; set; } = true;
}

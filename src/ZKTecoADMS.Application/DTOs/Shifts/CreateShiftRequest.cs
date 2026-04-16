namespace ZKTecoADMS.Application.DTOs.Shifts;

public class CreateShiftRequest
{
    public Guid? EmployeeUserId { get; set; }
    public List<WorkingDay> WorkingDays { get; set; } = [];
    public int MaximumAllowedLateMinutes { get; set; } = 30;
    public int MaximumAllowedEarlyLeaveMinutes { get; set; } = 30;

    public int BreakTimeMinutes { get; set; } = 60;
    public string? Description { get; set; }

}

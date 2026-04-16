using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.DTOs.Shifts;

public class UpdateShiftRequest
{
    public DateTime StartTime { get; set; }
    public DateTime EndTime { get; set; }
    public int MaximumAllowedLateMinutes { get; set; } = 30;
    public int MaximumAllowedEarlyLeaveMinutes { get; set; } = 30;
    public string? Description { get; set; }
    
    public LeaveStatus? Status { get; set; }
}

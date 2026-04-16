using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.DTOs.Shifts;

public class ShiftDto
{
    public Guid Id { get; set; }
    public Guid EmployeeUserId { get; set; }
    public Guid EmployeeId { get; set; }
    public string EmployeeName { get; set; } = string.Empty;
    public DateTime StartTime { get; set; }
    public DateTime EndTime { get; set; }
    public int MaximumAllowedLateMinutes { get; set; } = 30;
    public int MaximumAllowedEarlyLeaveMinutes { get; set; } = 30;
    public int BreakTimeMinutes { get; set; } = 60;
    public string? Description { get; set; }
    public ShiftStatus Status { get; set; }
    public DateTime? ApprovedAt { get; set; }
    public string? RejectionReason { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime? UpdatedAt { get; set; }
    public int TotalHours => EndTime.Subtract(StartTime).Hours;
    public DateTime? CheckInTime { get; set; }
    public DateTime? CheckOutTime { get; set; }
}

using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.DTOs.Leaves;

public class CreateLeaveRequest
{
    public Guid? EmployeeUserId { get; set; }
    public Guid? EmployeeId { get; set; }
    public LeaveType Type { get; set; }
    public Guid ShiftId { get; set; }
    public List<Guid>? ShiftIds { get; set; }
    public DateTime StartDate { get; set; }
    public DateTime EndDate { get; set; }
    public bool IsHalfShift { get; set; }
    public string Reason { get; set; } = string.Empty;
    public Guid? ReplacementEmployeeId { get; set; }
}

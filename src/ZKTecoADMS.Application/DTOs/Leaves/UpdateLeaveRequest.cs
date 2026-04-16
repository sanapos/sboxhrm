using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.DTOs.Leaves;

public class UpdateLeaveRequest
{
    public LeaveType Type { get; set; }
    public Guid ShiftId { get; set; }
    public List<Guid>? ShiftIds { get; set; }
    public DateTime StartDate { get; set; }
    public DateTime EndDate { get; set; }
    public bool IsHalfShift { get; set; }
    public string Reason { get; set; } = string.Empty;
    public LeaveStatus? Status { get; set; }
    public Guid? ReplacementEmployeeId { get; set; }
    public Guid? EmployeeId { get; set; }
}

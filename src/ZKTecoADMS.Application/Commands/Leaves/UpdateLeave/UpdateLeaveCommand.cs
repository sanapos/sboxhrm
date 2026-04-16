using ZKTecoADMS.Application.DTOs.Leaves;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.Leaves.UpdateLeave;

public record UpdateLeaveCommand(
    Guid StoreId,
    Guid LeaveId,
    Guid CurrentUserId,
    bool IsManager,
    Guid ShiftId,
    List<Guid>? ShiftIds,
    DateTime StartDate,
    DateTime EndDate,
    LeaveType Type,
    bool IsHalfShift,
    string Reason,
    LeaveStatus? Status,
    Guid? ReplacementEmployeeId,
    Guid? EmployeeId) : ICommand<AppResponse<LeaveDto>>;

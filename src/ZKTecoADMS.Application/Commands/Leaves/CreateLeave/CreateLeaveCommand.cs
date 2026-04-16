using ZKTecoADMS.Application.DTOs.Leaves;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.Leaves.CreateLeave;

public record CreateLeaveCommand(
    Guid StoreId,
    Guid EmployeeUserId,
    Guid ManagerId,
    Guid ShiftId,
    List<Guid>? ShiftIds,
    DateTime StartDate,
    DateTime EndDate,
    LeaveType Type,
    bool IsHalfShift,
    string Reason,
    Guid? ReplacementEmployeeId,
    Guid? EmployeeId) : ICommand<AppResponse<LeaveDto>>;

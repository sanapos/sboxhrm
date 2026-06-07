using ZKTecoADMS.Application.DTOs.Leaves;

namespace ZKTecoADMS.Application.Commands.Leaves.ApproveLeave;

public record ApproveLeaveCommand(Guid StoreId, Guid LeaveId, Guid ApprovedByUserId, bool? CountAsWork) : ICommand<AppResponse<bool>>;

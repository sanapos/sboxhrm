namespace ZKTecoADMS.Application.Commands.Leaves.UndoLeaveApproval;

public record UndoLeaveApprovalCommand(Guid StoreId, Guid LeaveId, Guid UserId) : ICommand<AppResponse<bool>>;

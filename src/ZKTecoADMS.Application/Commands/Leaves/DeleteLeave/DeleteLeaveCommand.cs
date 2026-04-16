namespace ZKTecoADMS.Application.Commands.Leaves.DeleteLeave;

public record DeleteLeaveCommand(Guid StoreId, Guid LeaveId, Guid UserId, bool IsManager) : ICommand<AppResponse<bool>>;

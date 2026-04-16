namespace ZKTecoADMS.Application.Commands.Leaves.ForceDeleteLeave;

public record ForceDeleteLeaveCommand(Guid StoreId, Guid LeaveId, Guid ApplicationUserId, bool IsManager)
    : ICommand<AppResponse<bool>>;

using ZKTecoADMS.Application.DTOs.Leaves;

namespace ZKTecoADMS.Application.Commands.Leaves.CancelLeave;

public record CancelLeaveCommand(Guid StoreId, Guid LeaveId, Guid ApplicationUserId, bool IsManager) : ICommand<AppResponse<bool>>;

using ZKTecoADMS.Application.DTOs.Leaves;

namespace ZKTecoADMS.Application.Commands.Leaves.RejectLeave;

public record RejectLeaveCommand(
    Guid StoreId,
    Guid LeaveId, 
    Guid RejectedByUserId, 
    string RejectionReason) : ICommand<AppResponse<bool>>;

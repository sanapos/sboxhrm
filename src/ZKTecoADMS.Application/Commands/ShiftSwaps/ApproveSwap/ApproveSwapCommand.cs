namespace ZKTecoADMS.Application.Commands.ShiftSwaps.ApproveSwap;

public record ApproveSwapCommand(
    Guid StoreId,
    Guid SwapRequestId,
    Guid ManagerId,
    bool Approve,
    string? RejectionReason,
    string? Note) : ICommand<AppResponse<bool>>;

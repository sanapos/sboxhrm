namespace ZKTecoADMS.Application.Commands.ShiftSwaps.RespondToSwap;

public record RespondToSwapCommand(
    Guid StoreId,
    Guid SwapRequestId,
    Guid TargetUserId,
    bool Accept,
    string? RejectionReason) : ICommand<AppResponse<bool>>;

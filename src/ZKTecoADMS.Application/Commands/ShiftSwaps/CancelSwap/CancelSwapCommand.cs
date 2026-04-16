namespace ZKTecoADMS.Application.Commands.ShiftSwaps.CancelSwap;

public record CancelSwapCommand(
    Guid StoreId,
    Guid SwapRequestId,
    Guid RequesterUserId) : ICommand<AppResponse<bool>>;

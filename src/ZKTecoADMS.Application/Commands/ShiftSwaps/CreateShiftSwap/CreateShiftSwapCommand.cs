using ZKTecoADMS.Application.DTOs.ShiftSwaps;

namespace ZKTecoADMS.Application.Commands.ShiftSwaps.CreateShiftSwap;

public record CreateShiftSwapCommand(
    Guid StoreId,
    Guid RequesterUserId,
    Guid TargetUserId,
    DateTime RequesterDate,
    Guid RequesterShiftId,
    DateTime TargetDate,
    Guid TargetShiftId,
    string? Reason) : ICommand<AppResponse<ShiftSwapRequestDto>>;

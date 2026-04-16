using ZKTecoADMS.Application.DTOs.Shifts;

namespace ZKTecoADMS.Application.Commands.Shifts.UpdateShift;

public record UpdateShiftCommand(
    Guid StoreId,
    Guid Id,
    Guid UpdatedByUserId,
    DateTime? CheckInTime,
    DateTime? CheckOutTime) : ICommand<AppResponse<ShiftDto>>;

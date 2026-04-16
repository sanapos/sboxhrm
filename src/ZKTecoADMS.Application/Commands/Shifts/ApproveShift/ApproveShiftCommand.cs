using ZKTecoADMS.Application.DTOs.Shifts;

namespace ZKTecoADMS.Application.Commands.Shifts.ApproveShift;

public record ApproveShiftCommand(
    Guid StoreId,
    Guid Id,
    Guid ApprovedByUserId) : ICommand<AppResponse<ShiftDto>>;

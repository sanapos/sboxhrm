namespace ZKTecoADMS.Application.Commands.Shifts.DeleteShift;

public record DeleteShiftCommand(Guid StoreId, Guid Id) : ICommand<AppResponse<bool>>;

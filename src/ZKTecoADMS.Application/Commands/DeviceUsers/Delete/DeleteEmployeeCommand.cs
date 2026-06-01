namespace ZKTecoADMS.Application.Commands.DeviceUsers.Delete;

public record DeleteDeviceUserCommand(Guid EmployeeId, bool SyncToDevice = true) : ICommand<AppResponse<Guid>>;
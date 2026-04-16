namespace ZKTecoADMS.Application.Commands.DeviceUsers.Delete;

public record DeleteDeviceUserCommand(Guid EmployeeId) : ICommand<AppResponse<Guid>>;
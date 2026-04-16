namespace ZKTecoADMS.Application.Commands.Devices.DeleteDevice;

public record DeleteDeviceCommand(Guid Id) : ICommand<AppResponse<Guid>>;
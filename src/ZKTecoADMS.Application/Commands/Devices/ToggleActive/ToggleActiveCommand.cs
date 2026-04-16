using ZKTecoADMS.Application.DTOs.Devices;

namespace ZKTecoADMS.Application.Commands.Devices.ToggleActive;

public record ToggleActiveCommand(Guid DeviceId) : ICommand<AppResponse<DeviceDto>>;
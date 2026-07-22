using ZKTecoADMS.Application.DTOs.Devices;

namespace ZKTecoADMS.Application.Commands.DeviceCommands.CreateDeviceCmd;

public record CreateDeviceCmdCommand(
    Guid DeviceId,
    int CommandType,
    int Priority,
    string? Command = null,
    string? Pin = null,
    int? FingerIndex = null) : ICommand<AppResponse<DeviceCmdDto>>;

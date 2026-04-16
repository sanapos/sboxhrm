using ZKTecoADMS.Application.DTOs.Devices;

namespace ZKTecoADMS.Application.Queries.DeviceCommands.GetCommandsByDevice;

public record GetCommandsByDeviceQuery(Guid DeviceId) : IQuery<AppResponse<IEnumerable<DeviceCmdDto>>>;

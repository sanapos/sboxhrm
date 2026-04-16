using ZKTecoADMS.Application.DTOs.Devices;

namespace ZKTecoADMS.Application.Queries.DeviceCommands.GetPendingCommands;

public record GetPendingCmdQuery(Guid DeviceId) : IQuery<AppResponse<IEnumerable<DeviceCmdDto>>>;

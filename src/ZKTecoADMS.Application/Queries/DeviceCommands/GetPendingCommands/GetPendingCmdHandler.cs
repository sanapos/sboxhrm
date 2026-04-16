using ZKTecoADMS.Application.DTOs.Devices;
using ZKTecoADMS.Application.Interfaces;

namespace ZKTecoADMS.Application.Queries.DeviceCommands.GetPendingCommands;

public class GetPendingCmdHandler(IDeviceService deviceService) : IQueryHandler<GetPendingCmdQuery, AppResponse<IEnumerable<DeviceCmdDto>>>
{
    public async Task<AppResponse<IEnumerable<DeviceCmdDto>>> Handle(GetPendingCmdQuery request, CancellationToken cancellationToken)
    {
        var pendingCmds = await deviceService.GetPendingCommandsAsync(request.DeviceId);

        return AppResponse<IEnumerable<DeviceCmdDto>>.Success(pendingCmds.Adapt<IEnumerable<DeviceCmdDto>>());
    }
}

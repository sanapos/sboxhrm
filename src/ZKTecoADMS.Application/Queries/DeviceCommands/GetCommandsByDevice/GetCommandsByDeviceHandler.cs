using Mapster;
using ZKTecoADMS.Application.DTOs.Devices;

namespace ZKTecoADMS.Application.Queries.DeviceCommands.GetCommandsByDevice;

public class GetCommandsByDeviceHandler(IRepository<DeviceCommand> deviceCmdRepository) : IQueryHandler<GetCommandsByDeviceQuery, AppResponse<IEnumerable<DeviceCmdDto>>>
{
    public async Task<AppResponse<IEnumerable<DeviceCmdDto>>> Handle(GetCommandsByDeviceQuery request, CancellationToken cancellationToken)
    {
        var commands = await deviceCmdRepository.GetAllAsync(
            dc => dc.DeviceId == request.DeviceId,
            orderBy: queryable => queryable.OrderByDescending(c => c.CreatedAt), 
            cancellationToken: cancellationToken
        );
        
        return AppResponse<IEnumerable<DeviceCmdDto>>.Success(commands.Adapt<IEnumerable<DeviceCmdDto>>());
    }
}

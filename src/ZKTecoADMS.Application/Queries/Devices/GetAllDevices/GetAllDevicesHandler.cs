using Mapster;
using ZKTecoADMS.Application.DTOs.Devices;
using ZKTecoADMS.Application.Interfaces;

namespace ZKTecoADMS.Application.Queries.Devices.GetAllDevices;

public class GetAllDevicesHandler(IRepository<Device> deviceRepository) : IQueryHandler<GetAllDevicesQuery, AppResponse<IEnumerable<DeviceDto>>>
{

    public async Task<AppResponse<IEnumerable<DeviceDto>>> Handle(GetAllDevicesQuery request, CancellationToken cancellationToken)
    {
        IEnumerable<Device> results;
        
        // If StoreId is provided, filter by store
        if (request.StoreId.HasValue)
        {
            results = await deviceRepository.GetAllAsync(
                filter: d => d.StoreId == request.StoreId.Value,
                cancellationToken: cancellationToken
            );
        }
        // Admin gets all devices, Manager/others get only their devices
        else if (request.IsAdminRequest)
        {
            results = await deviceRepository.GetAllAsync(
                cancellationToken: cancellationToken
            );
        }
        else
        {
            // Filter by userId for non-admin users
            results = await deviceRepository.GetAllAsync(
                filter: d => d.ManagerId == request.UserId,
                cancellationToken: cancellationToken
            );
        }
        
        return AppResponse<IEnumerable<DeviceDto>>.Success(results.Adapt<IEnumerable<DeviceDto>>());
    }
}

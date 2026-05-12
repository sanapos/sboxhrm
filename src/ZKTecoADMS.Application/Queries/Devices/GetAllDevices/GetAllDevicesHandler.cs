using Mapster;
using ZKTecoADMS.Application.DTOs.Devices;
using ZKTecoADMS.Application.Interfaces;

namespace ZKTecoADMS.Application.Queries.Devices.GetAllDevices;

public class GetAllDevicesHandler(IRepository<Device> deviceRepository) : IQueryHandler<GetAllDevicesQuery, AppResponse<IEnumerable<DeviceDto>>>
{
    public async Task<AppResponse<IEnumerable<DeviceDto>>> Handle(GetAllDevicesQuery request, CancellationToken cancellationToken)
    {
        var results = await deviceRepository.GetAllAsync(
            filter: null,
            cancellationToken: cancellationToken
        );

        IEnumerable<Device> filtered = results;

        if (request.StoreId.HasValue)
        {
            filtered = filtered.Where(d => d.StoreId == request.StoreId.Value);
        }
        else if (!request.IsAdminRequest)
        {
            filtered = filtered.Where(d => d.ManagerId == request.UserId);
        }

        return AppResponse<IEnumerable<DeviceDto>>.Success(filtered.Adapt<IEnumerable<DeviceDto>>());
    }
}

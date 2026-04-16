using ZKTecoADMS.Application.DTOs.Devices;

namespace ZKTecoADMS.Application.Queries.Devices.GetDeviceById;

public class GetDeviceByIdHandler(IRepository<Device> deviceRepository) 
    : IQueryHandler<GetDeviceByIdQuery, AppResponse<DeviceDto>>
{
    public async Task<AppResponse<DeviceDto>> Handle(GetDeviceByIdQuery request, CancellationToken cancellationToken)
    {
        var device = await deviceRepository.GetByIdAsync(request.Id, cancellationToken: cancellationToken);
        return AppResponse<DeviceDto>.Success(device.Adapt<DeviceDto>());
    }
}

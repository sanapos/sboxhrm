using ZKTecoADMS.Application.CQRS;
using ZKTecoADMS.Application.DTOs.Devices;

namespace ZKTecoADMS.Application.Queries.Devices.GetDeviceInfo;

public class GetDeviceInfoHandler(
IRepository<DeviceInfo> deviceInfoRepository
) : IQueryHandler<GetDeviceInfoQuery, AppResponse<DeviceInfoDto>>
{
    public async Task<AppResponse<DeviceInfoDto>> Handle(GetDeviceInfoQuery request, CancellationToken cancellationToken)
    {
        // Implementation for retrieving device information
        var info = await deviceInfoRepository.GetSingleAsync(di => di.DeviceId == request.Id, cancellationToken: cancellationToken);

        return AppResponse<DeviceInfoDto>.Success(info.Adapt<DeviceInfoDto>());

    }
}
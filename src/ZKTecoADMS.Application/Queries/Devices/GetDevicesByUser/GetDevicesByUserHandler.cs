using Mapster;
using ZKTecoADMS.Application.CQRS;
using ZKTecoADMS.Application.DTOs.Devices;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Application.Queries.Devices.GetDevicesByUser;
public class GetDevicesByUserHandler(IRepository<Device> deviceRepository) : IQueryHandler<GetDevicesByUserQuery, AppResponse<IEnumerable<DeviceDto>>>
{
    public async Task<AppResponse<IEnumerable<DeviceDto>>> Handle(GetDevicesByUserQuery request, CancellationToken cancellationToken)
    {
        var devices = await deviceRepository
            .GetAllAsync(d => d.ManagerId == request.UserId, cancellationToken: cancellationToken);

        return AppResponse<IEnumerable<DeviceDto>>.Success(devices.Adapt<IEnumerable<DeviceDto>>());
    }
}
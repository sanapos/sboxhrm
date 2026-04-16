using ZKTecoADMS.Application.DTOs.DeviceUsers;

namespace ZKTecoADMS.Application.Queries.DeviceUsers.GetDeviceUserDevices;

public record GetDeviceUserDevicesQuery(
    IEnumerable<Guid> DeviceIds
) : IQuery<AppResponse<IEnumerable<DeviceUserDto>>>;

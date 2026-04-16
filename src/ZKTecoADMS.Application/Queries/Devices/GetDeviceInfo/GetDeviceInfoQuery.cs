using ZKTecoADMS.Application.CQRS;
using ZKTecoADMS.Application.DTOs.Devices;

namespace ZKTecoADMS.Application.Queries.Devices.GetDeviceInfo;

public record GetDeviceInfoQuery(Guid Id) : IQuery<AppResponse<DeviceInfoDto>>;
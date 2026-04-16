using ZKTecoADMS.Application.CQRS;
using ZKTecoADMS.Application.DTOs.Devices;

namespace ZKTecoADMS.Application.Queries.Devices.GetDeviceById;

public record GetDeviceByIdQuery(Guid Id) : IQuery<AppResponse<DeviceDto>>;

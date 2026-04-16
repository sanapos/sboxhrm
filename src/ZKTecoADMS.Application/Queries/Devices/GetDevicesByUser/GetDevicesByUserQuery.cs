using ZKTecoADMS.Application.CQRS;
using ZKTecoADMS.Application.DTOs.Devices;
using ZKTecoADMS.Application.Models;

namespace ZKTecoADMS.Application.Queries.Devices.GetDevicesByUser;

public record GetDevicesByUserQuery(Guid UserId) : IQuery<AppResponse<IEnumerable<DeviceDto>>>;
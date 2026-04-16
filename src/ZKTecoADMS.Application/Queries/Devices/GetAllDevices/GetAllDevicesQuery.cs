using ZKTecoADMS.Application.CQRS;
using ZKTecoADMS.Application.DTOs.Devices;
using ZKTecoADMS.Application.Models;

namespace ZKTecoADMS.Application.Queries.Devices.GetAllDevices;

public record GetAllDevicesQuery(
    Guid? UserId = null, 
    bool IsAdminRequest = false,
    Guid? StoreId = null
) : IQuery<AppResponse<IEnumerable<DeviceDto>>>;

using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Application.Interfaces;

public interface IDeviceUserService
{
    Task<DeviceUser?> GetDeviceUserByPinAsync(Guid deviceId, string pin);
    Task<IEnumerable<DeviceUser>> CreateDeviceUsersAsync(Guid deviceId, IEnumerable<DeviceUser> employees);
}
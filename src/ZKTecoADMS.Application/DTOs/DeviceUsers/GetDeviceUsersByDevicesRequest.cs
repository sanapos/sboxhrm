namespace ZKTecoADMS.Application.DTOs.DeviceUsers;

public record GetDeviceUsersByDevicesRequest(IEnumerable<Guid> DeviceIds);
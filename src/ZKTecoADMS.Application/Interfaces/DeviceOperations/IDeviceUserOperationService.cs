namespace ZKTecoADMS.Application.Interfaces;

/// <summary>
/// Service interface for parsing and processing employee data from device OPERLOG data.
/// </summary>
public interface IDeviceUserOperationService
{
    /// <summary>
    /// Parses and processes employee data from device OPERLOG format.
    /// </summary>
    Task<List<DeviceUser>> ProcessUsersFromDeviceAsync(Device device, string body);
}

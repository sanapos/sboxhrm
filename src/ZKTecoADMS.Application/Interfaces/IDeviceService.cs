using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Interfaces;

public interface IDeviceService
{
    Task<Device?> GetDeviceBySerialNumberAsync(string serialNumber);
    Task<bool> IsExistDeviceAsync(string serialNumber);
    Task UpdateDeviceHeartbeatAsync(string serialNumber);
    Task<IEnumerable<DeviceCommand>> GetPendingCommandsAsync(Guid deviceId);
    Task<DeviceCommand> CreateCommandAsync(DeviceCommand command);
    Task<AppResponse<bool>> IsUserValid(DeviceUser deviceUser);
    Task<IEnumerable<Device>> GetAllDevicesByEmployeeAsync(Guid employeeId);
    
    /// <summary>
    /// Tạo thiết bị mới (Active) từ form thêm thiết bị
    /// </summary>
    Task<Device> CreateDeviceAsync(Device device);
    
    /// <summary>
    /// Tạo thiết bị mới với trạng thái Pending khi nhận request từ thiết bị chưa đăng ký
    /// </summary>
    Task<Device> CreatePendingDeviceAsync(string serialNumber, string? ipAddress = null);
    
    /// <summary>
    /// Lấy danh sách thiết bị đang chờ duyệt (Pending)
    /// </summary>
    Task<IEnumerable<Device>> GetPendingDevicesAsync();
    
    /// <summary>
    /// Duyệt thiết bị - chuyển từ Pending sang Active
    /// </summary>
    Task<Device?> ApproveDeviceAsync(Guid deviceId, string deviceName, string? description = null, string? location = null);
    
    /// <summary>
    /// Tự động kích hoạt thiết bị khi cửa hàng đã claim đúng SN
    /// </summary>
    Task AutoActivateDeviceAsync(string serialNumber);
    
    /// <summary>
    /// Từ chối thiết bị - xóa khỏi danh sách pending
    /// </summary>
    Task<bool> RejectDeviceAsync(Guid deviceId);
    
    /// <summary>
    /// Lấy danh sách thiết bị đang online (đã kết nối trong vòng 5 phút)
    /// </summary>
    Task<IEnumerable<Device>> GetConnectedDevicesAsync();
    
    /// <summary>
    /// Lấy danh sách thiết bị chưa được claim (available để user claim)
    /// </summary>
    Task<IEnumerable<Device>> GetAvailableDevicesAsync();
    
    /// <summary>
    /// User claim thiết bị bằng Serial Number
    /// </summary>
    Task<AppResponse<Device>> ClaimDeviceAsync(Guid userId, string serialNumber, string deviceName, string? description = null, string? location = null);
    
    /// <summary>
    /// Lấy danh sách thiết bị của một user (đã claim)
    /// </summary>
    Task<IEnumerable<Device>> GetDevicesByOwnerAsync(Guid ownerId);
    
    /// <summary>
    /// Unclaim thiết bị - trả lại thiết bị về trạng thái available
    /// </summary>
    Task<AppResponse<bool>> UnclaimDeviceAsync(Guid deviceId, Guid userId);
}
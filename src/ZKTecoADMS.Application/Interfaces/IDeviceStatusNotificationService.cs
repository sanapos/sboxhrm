using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Application.Interfaces;

/// <summary>
/// Interface for sending real-time device status notifications via SignalR
/// </summary>
public interface IDeviceStatusNotificationService
{
    /// <summary>
    /// Notify all clients when a device comes online
    /// </summary>
    Task NotifyDeviceOnlineAsync(Device device);
    
    /// <summary>
    /// Notify all clients when a device goes offline
    /// </summary>
    Task NotifyDeviceOfflineAsync(Device device);
    
    /// <summary>
    /// Notify all clients when a new device is detected (pending approval)
    /// </summary>
    Task NotifyNewDeviceDetectedAsync(Device device);

    /// <summary>
    /// Cảnh báo từ gateway ESP32: mất máy chấm công LAN, lỗi giao tiếp, sync quá lâu...
    /// </summary>
    Task NotifyDeviceAlertAsync(Device device, string code, string message, int records = 0, long durationMs = 0);
}

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
}

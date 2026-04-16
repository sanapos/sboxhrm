using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Hubs;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Service for sending real-time device status notifications via SignalR
/// Targets: admin users in the same store + SuperAdmins
/// </summary>
public class DeviceStatusNotificationService : IDeviceStatusNotificationService
{
    private readonly IHubContext<AttendanceHub> _hubContext;
    private readonly IRepository<Notification> _notificationRepository;
    private readonly IRepository<NotificationPreference> _preferenceRepository;
    private readonly UserManager<ApplicationUser> _userManager;
    private readonly ILogger<DeviceStatusNotificationService> _logger;

    public DeviceStatusNotificationService(
        IHubContext<AttendanceHub> hubContext,
        IRepository<Notification> notificationRepository,
        IRepository<NotificationPreference> preferenceRepository,
        UserManager<ApplicationUser> userManager,
        ILogger<DeviceStatusNotificationService> logger)
    {
        _hubContext = hubContext;
        _notificationRepository = notificationRepository;
        _preferenceRepository = preferenceRepository;
        _userManager = userManager;
        _logger = logger;
    }

    public async Task NotifyDeviceOnlineAsync(Device device)
    {
        try
        {
            var message = $"Máy chấm công '{device.DeviceName ?? device.SerialNumber}' đã kết nối";
            
            var notification = new DeviceStatusNotification(
                DeviceId: device.Id.ToString(),
                SerialNumber: device.SerialNumber,
                DeviceName: device.DeviceName ?? device.SerialNumber,
                Location: device.Location,
                Status: "Online",
                EventType: "DeviceOnline",
                Timestamp: DateTime.UtcNow,
                Message: message
            );

            var adminUserIds = await GetAdminUserIdsAsync(device);
            await SendDeviceStatusToTargetsAsync(notification, adminUserIds, device);

            await SendAndSaveNotificationAsync(
                title: "Thiết bị kết nối",
                message: message,
                type: NotificationType.Success,
                adminUserIds: adminUserIds,
                relatedEntityId: device.Id,
                relatedEntityType: "Device",
                storeId: device.StoreId
            );
            
            _logger.LogInformation("📡 Device ONLINE notification: {DeviceName}, Targets={Count}", 
                device.DeviceName, adminUserIds.Count);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to send device online notification for {SN}", device.SerialNumber);
        }
    }

    public async Task NotifyDeviceOfflineAsync(Device device)
    {
        try
        {
            var message = $"Máy chấm công '{device.DeviceName ?? device.SerialNumber}' đã ngắt kết nối";
            
            var notification = new DeviceStatusNotification(
                DeviceId: device.Id.ToString(),
                SerialNumber: device.SerialNumber,
                DeviceName: device.DeviceName ?? device.SerialNumber,
                Location: device.Location,
                Status: "Offline",
                EventType: "DeviceOffline",
                Timestamp: DateTime.UtcNow,
                Message: message
            );

            var adminUserIds = await GetAdminUserIdsAsync(device);
            await SendDeviceStatusToTargetsAsync(notification, adminUserIds, device);

            await SendAndSaveNotificationAsync(
                title: "Thiết bị ngắt kết nối",
                message: message,
                type: NotificationType.Warning,
                adminUserIds: adminUserIds,
                relatedEntityId: device.Id,
                relatedEntityType: "Device",
                storeId: device.StoreId
            );
            
            _logger.LogInformation("📡 Device OFFLINE notification: {DeviceName}, Targets={Count}", 
                device.DeviceName, adminUserIds.Count);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to send device offline notification for {SN}", device.SerialNumber);
        }
    }

    public async Task NotifyNewDeviceDetectedAsync(Device device)
    {
        try
        {
            var message = $"Phát hiện máy chấm công mới: {device.SerialNumber}";
            
            var notification = new DeviceStatusNotification(
                DeviceId: device.Id.ToString(),
                SerialNumber: device.SerialNumber,
                DeviceName: device.DeviceName ?? device.SerialNumber,
                Location: device.Location,
                Status: "Pending",
                EventType: "NewDeviceDetected",
                Timestamp: DateTime.UtcNow,
                Message: message
            );

            var adminUserIds = await GetAdminUserIdsAsync(device);
            await SendDeviceStatusToTargetsAsync(notification, adminUserIds, device);

            await SendAndSaveNotificationAsync(
                title: "Phát hiện thiết bị mới",
                message: message,
                type: NotificationType.Info,
                adminUserIds: adminUserIds,
                relatedEntityId: device.Id,
                relatedEntityType: "Device",
                storeId: device.StoreId
            );
            
            _logger.LogInformation("📡 New device detected: SN={SN}, Targets={Count}", 
                device.SerialNumber, adminUserIds.Count);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to send new device detected notification for {SN}", device.SerialNumber);
        }
    }

    /// <summary>
    /// Get admin user IDs in the same store + all SuperAdmins, filtered by notification preferences
    /// </summary>
    private async Task<HashSet<Guid>> GetAdminUserIdsAsync(Device device)
    {
        var admins = await _userManager.Users
            .Where(u => u.IsActive && (u.Role == "SuperAdmin" ||
                 (u.Role == "Admin" && device.StoreId.HasValue && u.StoreId == device.StoreId)))
            .ToListAsync();
        var adminUserIds = admins.Select(u => u.Id).ToHashSet();

        // Filter out users who disabled "device" notification category
        if (adminUserIds.Count > 0)
        {
            var userIdList = adminUserIds.ToList();
            var disabledPrefs = await _preferenceRepository.GetAllAsync(
                p => userIdList.Contains(p.UserId)
                     && p.CategoryCode == "device"
                     && !p.IsEnabled
                     && (p.StoreId == null || p.StoreId == device.StoreId));
            adminUserIds.ExceptWith(disabledPrefs.Select(p => p.UserId));
        }

        return adminUserIds;
    }

    /// <summary>
    /// Send DeviceStatusChanged to targeted admin user groups only
    /// </summary>
    private async Task SendDeviceStatusToTargetsAsync(
        DeviceStatusNotification notification, HashSet<Guid> adminUserIds, Device device)
    {
        if (adminUserIds.Count > 0)
        {
            var groups = adminUserIds.Select(id => $"user_{id}").ToList();
            await _hubContext.Clients.Groups(groups).SendAsync("DeviceStatusChanged", notification);
        }
        else
        {
            _logger.LogWarning("⚠️ No target admins for device status notification: {DeviceName}", device.DeviceName);
        }
    }

    /// <summary>
    /// Save per-user notification records and send NewNotification via SignalR.
    /// No fallback broadcast — only per-user records are created.
    /// </summary>
    private async Task SendAndSaveNotificationAsync(
        string title,
        string message,
        NotificationType type,
        HashSet<Guid> adminUserIds,
        Guid? relatedEntityId = null,
        string? relatedEntityType = null,
        Guid? storeId = null)
    {
        try
        {
            if (adminUserIds.Count == 0)
            {
                _logger.LogWarning("⚠️ No target admins for device notification: {Title}", title);
                return;
            }

            var notifications = adminUserIds.Select(uid => new Notification
            {
                TargetUserId = uid,
                Type = type,
                Title = title,
                Message = message,
                Timestamp = DateTime.UtcNow,
                IsRead = false,
                RelatedEntityId = relatedEntityId,
                RelatedEntityType = relatedEntityType,
                RelatedUrl = "/adms-devices",
                CategoryCode = "device",
                StoreId = storeId
            }).ToList();

            await _notificationRepository.AddRangeAsync(notifications);

            foreach (var n in notifications)
            {
                var dto = new
                {
                    id = n.Id,
                    title = n.Title,
                    message = n.Message,
                    type = (int)n.Type,
                    timestamp = n.Timestamp,
                    isRead = false,
                    relatedUrl = n.RelatedUrl,
                    relatedEntityId = n.RelatedEntityId,
                    relatedEntityType = n.RelatedEntityType
                };
                await _hubContext.Clients.Group($"user_{n.TargetUserId}").SendAsync("NewNotification", dto);
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to save notification: {Title}", title);
        }
    }
}

/// <summary>
/// DTO for real-time device status notification
/// </summary>
public record DeviceStatusNotification(
    string DeviceId,
    string SerialNumber,
    string DeviceName,
    string? Location,
    string Status,
    string EventType,
    DateTime Timestamp,
    string Message
);

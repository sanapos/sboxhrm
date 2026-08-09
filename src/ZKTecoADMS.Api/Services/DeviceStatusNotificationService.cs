using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using ZKTecoADMS.Api.Hubs;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Notifications;
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
    private readonly IServiceScopeFactory _serviceScopeFactory;

    public DeviceStatusNotificationService(
        IHubContext<AttendanceHub> hubContext,
        IRepository<Notification> notificationRepository,
        IRepository<NotificationPreference> preferenceRepository,
        UserManager<ApplicationUser> userManager,
        ILogger<DeviceStatusNotificationService> logger,
        IServiceScopeFactory serviceScopeFactory)
    {
        _hubContext = hubContext;
        _notificationRepository = notificationRepository;
        _preferenceRepository = preferenceRepository;
        _userManager = userManager;
        _logger = logger;
        _serviceScopeFactory = serviceScopeFactory;
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

            var (adminUserIds, rolesByUserId) = await GetAdminUsersAsync(device);
            await SendDeviceStatusToTargetsAsync(notification, adminUserIds, device);

            await SendAndSaveNotificationAsync(
                title: "Thiết bị kết nối",
                message: message,
                type: NotificationType.Success,
                adminUserIds: adminUserIds,
                rolesByUserId: rolesByUserId,
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

            var (adminUserIds, rolesByUserId) = await GetAdminUsersAsync(device);
            await SendDeviceStatusToTargetsAsync(notification, adminUserIds, device);

            await SendAndSaveNotificationAsync(
                title: "Thiết bị ngắt kết nối",
                message: message,
                type: NotificationType.Warning,
                adminUserIds: adminUserIds,
                rolesByUserId: rolesByUserId,
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

            var (adminUserIds, rolesByUserId) = await GetAdminUsersAsync(device);
            await SendDeviceStatusToTargetsAsync(notification, adminUserIds, device);

            await SendAndSaveNotificationAsync(
                title: "Phát hiện thiết bị mới",
                message: message,
                type: NotificationType.Info,
                adminUserIds: adminUserIds,
                rolesByUserId: rolesByUserId,
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

    public async Task NotifyDeviceAlertAsync(Device device, string code, string message, int records = 0, long durationMs = 0)
    {
        try
        {
            var (title, eventType, type, status) = MapAlert(code);
            var name = device.DeviceName ?? device.SerialNumber;
            var detail = string.IsNullOrWhiteSpace(message)
                ? title
                : $"{message}";
            if (records > 0)
                detail += $" (log trên máy: {records:N0})";
            if (durationMs > 0)
                detail += $" (mất {durationMs / 1000.0:0.#}s)";

            var fullMessage = $"Gateway '{name}': {detail}";

            var notification = new DeviceStatusNotification(
                DeviceId: device.Id.ToString(),
                SerialNumber: device.SerialNumber,
                DeviceName: name,
                Location: device.Location,
                Status: status,
                EventType: eventType,
                Timestamp: DateTime.UtcNow,
                Message: fullMessage
            );

            var (adminUserIds, rolesByUserId) = await GetAdminUsersAsync(device);
            await SendDeviceStatusToTargetsAsync(notification, adminUserIds, device);

            await SendAndSaveNotificationAsync(
                title: title,
                message: fullMessage,
                type: type,
                adminUserIds: adminUserIds,
                rolesByUserId: rolesByUserId,
                relatedEntityId: device.Id,
                relatedEntityType: "Device",
                storeId: device.StoreId
            );

            _logger.LogInformation(
                "📡 Device ALERT {Code}: {DeviceName}, Targets={Count}",
                code, name, adminUserIds.Count);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to send device alert {Code} for {SN}", code, device.SerialNumber);
        }
    }

    private static (string Title, string EventType, NotificationType Type, string Status) MapAlert(string code)
    {
        return (code ?? "").Trim().ToUpperInvariant() switch
        {
            "ZK_OFFLINE" => ("Mất kết nối máy chấm công", "ZkOffline", NotificationType.Warning, "ZkOffline"),
            "ZK_ONLINE" => ("Máy chấm công đã kết nối lại", "ZkOnline", NotificationType.Success, "Online"),
            "COMM_ERROR" => ("Lỗi giao tiếp máy chấm công", "CommError", NotificationType.Warning, "CommError"),
            "SYNC_SLOW" => ("Đồng bộ quá lâu — nên xóa bớt log trên máy", "SyncSlow", NotificationType.Warning, "SyncSlow"),
            "SYNC_FAILED" => ("Đồng bộ chấm công thất bại", "SyncFailed", NotificationType.Error, "SyncFailed"),
            _ => ("Cảnh báo gateway chấm công", "GatewayAlert", NotificationType.Warning, "Alert"),
        };
    }

    /// <summary>
    /// Get admin user IDs in the same store + all SuperAdmins, filtered by notification preferences
    /// </summary>
    private async Task<(HashSet<Guid> UserIds, Dictionary<Guid, string> RolesByUserId)> GetAdminUsersAsync(Device device)
    {
        var admins = await _userManager.Users
            .Where(u => u.IsActive && (u.Role == "SuperAdmin" ||
                 (u.Role == "Admin" && device.StoreId.HasValue && u.StoreId == device.StoreId)))
            .Select(u => new { u.Id, u.Role })
            .ToListAsync();
        var rolesById = admins.ToDictionary(a => a.Id, a => a.Role ?? "");
        var adminUserIds = rolesById.Keys.ToHashSet();

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

        return (adminUserIds, rolesById);
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
        Dictionary<Guid, string> rolesByUserId,
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

            static string DeviceActionUrl(Guid userId, Dictionary<Guid, string> roles) =>
                roles.TryGetValue(userId, out var role)
                && string.Equals(role, "SuperAdmin", StringComparison.OrdinalIgnoreCase)
                    ? "/admin/devices"
                    : "/adms-devices";

            var notifications = adminUserIds.Select(uid => new Notification
            {
                Id = Guid.NewGuid(),
                TargetUserId = uid,
                Type = type,
                Title = title,
                Message = message,
                Timestamp = DateTime.UtcNow,
                IsRead = false,
                RelatedEntityId = relatedEntityId,
                RelatedEntityType = relatedEntityType,
                RelatedUrl = DeviceActionUrl(uid, rolesByUserId),
                CategoryCode = "device",
                StoreId = storeId
            }).ToList();

            await _notificationRepository.AddRangeAsync(notifications);

            // FCM push (app background/closed). Per-user so each device's tray entry
            // carries its own notificationId — tapping it can then mark the right row
            // as read on the server, which keeps the icon badge correct.
            try
            {
                using var pushScope = _serviceScopeFactory.CreateScope();
                var push = pushScope.ServiceProvider.GetService<ZKTecoADMS.Infrastructure.Services.Push.IPushNotificationService>();
                if (push != null)
                {
                    foreach (var n in notifications)
                    {
                        var display = NotificationPushFormatter.Format(n);
                        var pushData = NotificationDtoMapper.ToFcmData(n, display: display);
                        await push.PushToUserAsync(n.TargetUserId!.Value, display.Title, display.Body,
                            actionUrl: n.RelatedUrl, data: pushData);
                    }
                }
            }
            catch (Exception pushEx)
            {
                _logger.LogWarning(pushEx, "FCM push for device-status notification failed (non-fatal)");
            }

            foreach (var n in notifications)
            {
                try
                {
                    var display = NotificationPushFormatter.Format(n);
                    var dto = NotificationDtoMapper.ToSignalRPayload(n, display);
                    await _hubContext.Clients.Group($"user_{n.TargetUserId}").SendAsync("NewNotification", dto);
                }
                catch (Exception perUserEx)
                {
                    _logger.LogError(perUserEx,
                        "Failed to push device-status notification {NotificationId} to user {UserId}",
                        n.Id, n.TargetUserId);
                }
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

using System.Globalization;
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

    private static string DeviceLabel(Device device) =>
        string.IsNullOrWhiteSpace(device.DeviceName) ? device.SerialNumber : device.DeviceName.Trim();

    /// <summary>«HH:mm dd/MM» giờ VN (Timestamp/LastOnline lưu UTC).</summary>
    private static string VnStamp(DateTime utc) =>
        ZKTecoADMS.Application.Helpers.VnTimeHelper.UtcToVn(utc).ToString("HH:mm dd/MM", CultureInfo.InvariantCulture);

    /// <summary>Số kiểu Việt: 85000 → «85.000».</summary>
    private static string VnNumber(long value) =>
        value.ToString("#,0", CultureInfo.InvariantCulture).Replace(',', '.');

    /// <summary>
    /// Tên cửa hàng của máy — SuperAdmin nhận thông báo của mọi cửa hàng nên cần biết máy ở đâu.
    /// </summary>
    private async Task<string?> GetStoreNameAsync(Device device)
    {
        if (!string.IsNullOrWhiteSpace(device.Store?.Name)) return device.Store!.Name.Trim();
        if (!device.StoreId.HasValue) return null;
        try
        {
            using var scope = _serviceScopeFactory.CreateScope();
            var db = scope.ServiceProvider.GetService<ZKTecoADMS.Infrastructure.ZKTecoDbContext>();
            if (db == null) return null;
            var storeId = device.StoreId.Value;
            var name = await db.Stores.IgnoreQueryFilters().AsNoTracking()
                .Where(s => s.Id == storeId)
                .Select(s => s.Name)
                .FirstOrDefaultAsync();
            return string.IsNullOrWhiteSpace(name) ? null : name.Trim();
        }
        catch (Exception ex)
        {
            _logger.LogDebug(ex, "Could not resolve store name for device {SN}", device.SerialNumber);
            return null;
        }
    }

    /// <summary>Ghép các ý bằng « · », bỏ ý trống.</summary>
    private static string JoinParts(params string?[] parts) =>
        string.Join(" · ", parts.Where(p => !string.IsNullOrWhiteSpace(p)).Select(p => p!.Trim()));

    public async Task NotifyDeviceOnlineAsync(Device device)
    {
        try
        {
            var storeName = await GetStoreNameAsync(device);
            var message = JoinParts(DeviceLabel(device), storeName, $"lúc {VnStamp(DateTime.UtcNow)}");

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
                title: "Máy chấm công đã kết nối lại",
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
            var storeName = await GetStoreNameAsync(device);
            // LastOnline (UTC) = nhịp tim cuối — mốc máy bắt đầu mất kết nối.
            var since = VnStamp(device.LastOnline ?? DateTime.UtcNow);
            var message = JoinParts(DeviceLabel(device), storeName, $"từ {since}", "kiểm tra điện, mạng của máy");

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
                title: "Máy chấm công mất kết nối",
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
            var storeName = await GetStoreNameAsync(device);
            var message = JoinParts(
                $"Serial {device.SerialNumber}",
                storeName ?? "chưa gán cửa hàng",
                $"lúc {VnStamp(DateTime.UtcNow)}",
                "mở Thiết bị để duyệt");

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
                title: "Có máy chấm công mới",
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
            var name = DeviceLabel(device);
            var storeName = await GetStoreNameAsync(device);
            var normalizedCode = (code ?? "").Trim().ToUpperInvariant();

            // Body: máy · cửa hàng · giờ VN · số liệu (kiểu Việt) · việc cần làm / lý do gateway gửi lên.
            var parts = new List<string?> { name, storeName, $"lúc {VnStamp(DateTime.UtcNow)}" };
            if (records > 0)
                parts.Add($"{VnNumber(records)} lượt trên máy");
            if (durationMs > 0)
                parts.Add($"mất {(durationMs / 1000.0).ToString("0.#", CultureInfo.InvariantCulture).Replace('.', ',')} giây");
            if (normalizedCode == "SYNC_SLOW")
                parts.Add("nên xóa bớt log trên máy");
            else if (normalizedCode == "ZK_OFFLINE")
                parts.Add("kiểm tra điện, mạng của máy");
            else if (normalizedCode != "ZK_ONLINE" && !string.IsNullOrWhiteSpace(message))
                parts.Add(message.Trim()); // lý do chi tiết do gateway gửi lên (lỗi giao tiếp, đồng bộ lỗi, mã lạ)

            var fullMessage = JoinParts(parts.ToArray());

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
            "SYNC_SLOW" => ("Máy chấm công đồng bộ chậm", "SyncSlow", NotificationType.Warning, "SyncSlow"),
            "SYNC_FAILED" => ("Đồng bộ chấm công thất bại", "SyncFailed", NotificationType.Error, "SyncFailed"),
            _ => ("Cảnh báo máy chấm công", "GatewayAlert", NotificationType.Warning, "Alert"),
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

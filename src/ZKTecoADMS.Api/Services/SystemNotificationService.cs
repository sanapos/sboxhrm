using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Hubs;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Notifications;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Domain.Repositories;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Services.Push;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Service for sending real-time system notifications via SignalR
/// </summary>
public class SystemNotificationService : ISystemNotificationService
{
    private readonly IHubContext<AttendanceHub> _hubContext;
    private readonly ILogger<SystemNotificationService> _logger;
    private readonly IRepository<Notification> _notificationRepository;
    private readonly IRepository<NotificationPreference> _preferenceRepository;
    private readonly ZKTecoDbContext _dbContext;
    private readonly IPushNotificationService _push;

    public SystemNotificationService(
        IHubContext<AttendanceHub> hubContext,
        ILogger<SystemNotificationService> logger,
        IRepository<Notification> notificationRepository,
        IRepository<NotificationPreference> preferenceRepository,
        ZKTecoDbContext dbContext,
        IPushNotificationService push)
    {
        _hubContext = hubContext;
        _logger = logger;
        _notificationRepository = notificationRepository;
        _preferenceRepository = preferenceRepository;
        _dbContext = dbContext;
        _push = push;
    }

    public async Task SendToUserAsync(Guid userId, Notification notification)
    {
        var display = await BuildPushDisplayAsync(notification);
        try
        {
            var dto = NotificationDtoMapper.ToSignalRPayload(notification, display);
            await _hubContext.Clients.Group($"user_{userId}").SendAsync("NewNotification", dto);
            _logger.LogInformation("📢 Sent notification to user {UserId}: {Title}", userId, display.Title);
        }
        catch (Exception ex)
        {
            // Log notification id so the row can be re-pushed manually or by a future
            // retry job (the entity is already persisted by the caller before we get here).
            _logger.LogError(ex,
                "Failed to send notification {NotificationId} to user {UserId}; row remains in DB and will appear on next history reload",
                notification.Id, userId);
        }

        // Best-effort FCM fan-out (silent no-op when Firebase isn't configured).
        try
        {
            await _push.PushToUserAsync(userId, display.Title, display.Body,
                notification.RelatedUrl,
                NotificationDtoMapper.ToFcmData(notification, display: display));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "FCM push failed for notification {NotificationId}", notification.Id);
        }
    }

    public async Task SendToUsersAsync(IEnumerable<Guid> userIds, Notification notification)
    {
        var idList = userIds as IList<Guid> ?? userIds.ToList();
        var display = await BuildPushDisplayAsync(notification);
        try
        {
            var dto = NotificationDtoMapper.ToSignalRPayload(notification, display);
            var groupNames = idList.Select(id => $"user_{id}").ToList();
            await _hubContext.Clients.Groups(groupNames).SendAsync("NewNotification", dto);
            _logger.LogInformation("📢 Sent notification to {Count} users: {Title}", groupNames.Count, display.Title);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to send notification to multiple users");
        }

        try
        {
            await _push.PushToUsersAsync(idList, display.Title, display.Body,
                notification.RelatedUrl,
                NotificationDtoMapper.ToFcmData(notification, display: display));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "FCM bulk push failed for notification {NotificationId}", notification.Id);
        }
    }

    public async Task SendToAllAsync(Notification notification)
    {
        // SECURITY: previously this used Clients.All which leaks notifications across
        // tenants/stores. We now restrict the broadcast to the originating store if
        // we have one; only fall back to a true all-clients broadcast for genuinely
        // system-wide notifications (StoreId == null). Callers should target a store
        // explicitly to avoid the cross-tenant leak that motivated this fix.
        try
        {
            var display = await BuildPushDisplayAsync(notification);
            var dto = NotificationDtoMapper.ToSignalRPayload(notification, display);
            if (notification.StoreId.HasValue)
            {
                await _hubContext.Clients.Group($"store_{notification.StoreId.Value}")
                    .SendAsync("NewNotification", dto);
                _logger.LogInformation("📢 Broadcast notification to store {StoreId}: {Title}",
                    notification.StoreId.Value, notification.Title);
            }
            else
            {
                await _hubContext.Clients.All.SendAsync("NewNotification", dto);
                _logger.LogInformation("📢 Broadcast notification to all clients (system-wide): {Title}", notification.Title);
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to broadcast notification");
        }

        await PushFcmForBroadcastAsync(notification);
    }

    /// <summary>
    /// FCM for store-wide broadcasts (single shared notification row, TargetUserId null).
    /// </summary>
    private async Task PushFcmForBroadcastAsync(Notification notification)
    {
        if (!notification.StoreId.HasValue) return;

        try
        {
            var userIds = await _dbContext.Users
                .AsNoTracking()
                .Where(u => u.StoreId == notification.StoreId.Value && u.IsActive)
                .Select(u => u.Id)
                .ToListAsync();
            if (userIds.Count == 0) return;

            var display = await BuildPushDisplayAsync(notification);
            await _push.PushToUsersAsync(
                userIds,
                display.Title,
                display.Body,
                notification.RelatedUrl,
                NotificationDtoMapper.ToFcmData(notification, display: display),
                androidTag: notification.CategoryCode ?? "sbox_hrm");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex,
                "FCM broadcast push failed for notification {NotificationId}", notification.Id);
        }
    }

    public async Task CreateAndSendAsync(
        Guid? targetUserId,
        NotificationType type,
        string title,
        string message,
        string? relatedUrl = null,
        Guid? relatedEntityId = null,
        string? relatedEntityType = null,
        Guid? fromUserId = null,
        string? categoryCode = null,
        Guid? storeId = null)
    {
        try
        {
            // Check user notification preference if categoryCode is provided.
            // Both this single-user path and the batch CreateAndSendToUsersAsync
            // skip BEFORE persisting any Notification entity to keep history
            // consistent: a user who disabled a category should not see records
            // for it appearing in their list later.
            if (targetUserId.HasValue && !string.IsNullOrEmpty(categoryCode))
            {
                if (await IsCategoryDisabledForUserAsync(targetUserId.Value, categoryCode, storeId))
                {
                    _logger.LogInformation(
                        "Notification skipped: user {UserId} disabled category {Category} in store {StoreId}",
                        targetUserId.Value, NotificationCategoryCodes.Normalize(categoryCode), storeId);
                    return;
                }
            }

            // Create notification entity
            var notification = new Notification
            {
                Id = Guid.NewGuid(),
                TargetUserId = targetUserId,
                Type = type,
                Title = title,
                Message = message,
                Timestamp = DateTime.UtcNow,
                IsRead = false,
                FromUserId = fromUserId,
                RelatedUrl = relatedUrl,
                RelatedEntityId = relatedEntityId,
                RelatedEntityType = relatedEntityType,
                CategoryCode = NotificationCategoryCodes.Normalize(categoryCode) ?? categoryCode,
                StoreId = storeId
            };

            // Save to database FIRST. We only attempt to push via SignalR after the
            // row is committed - that way if the push fails, the user still sees the
            // notification when they reload the history page.
            await _notificationRepository.AddAsync(notification);

            // Send via SignalR (best-effort; failure logged but not rethrown
            // because the row is already durable).
            if (targetUserId.HasValue)
            {
                await SendToUserAsync(targetUserId.Value, notification);
            }
            else
            {
                // Broadcast to all if no specific user
                await SendToAllAsync(notification);
            }

            _logger.LogInformation("📢 Created and sent notification: Type={Type}, Title={Title}", type, title);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to create and send notification");
        }
    }

    public async Task CreateAndSendToUsersAsync(
        IEnumerable<Guid> targetUserIds,
        NotificationType type,
        string title,
        string message,
        string? relatedUrl = null,
        Guid? relatedEntityId = null,
        string? relatedEntityType = null,
        Guid? fromUserId = null,
        string? categoryCode = null,
        Guid? storeId = null)
    {
        try
        {
            var userIdList = targetUserIds.ToList();
            if (userIdList.Count == 0) return;

            // Load preferences for all users in one query
            var disabledUserIds = string.IsNullOrEmpty(categoryCode)
                ? new HashSet<Guid>()
                : await GetDisabledUserIdsAsync(userIdList, categoryCode, storeId);

            var notifications = new List<Notification>();

            foreach (var userId in userIdList)
            {
                if (disabledUserIds.Contains(userId)) continue;

                notifications.Add(new Notification
                {
                    Id = Guid.NewGuid(),
                    TargetUserId = userId,
                    Type = type,
                    Title = title,
                    Message = message,
                    Timestamp = DateTime.UtcNow,
                    IsRead = false,
                    FromUserId = fromUserId,
                    RelatedUrl = relatedUrl,
                    RelatedEntityId = relatedEntityId,
                    RelatedEntityType = relatedEntityType,
                    CategoryCode = NotificationCategoryCodes.Normalize(categoryCode) ?? categoryCode,
                    StoreId = storeId
                });
            }

            if (notifications.Count == 0) return;

            // Batch save all notifications BEFORE pushing via SignalR. The DB row
            // is the source of truth; any push that fails after this point can be
            // recovered by the client via /api/notifications.
            await _notificationRepository.AddRangeAsync(notifications);

            var senderNames = await ResolveSenderNamesAsync(
                notifications.Select(n => n.FromUserId));

            // Send individual notification DTOs to each user's group
            // Each user should receive their own notification with correct userId
            foreach (var notification in notifications)
            {
                if (notification.TargetUserId.HasValue)
                {
                    try
                    {
                        var display = BuildPushDisplay(notification, senderNames);
                        var dto = NotificationDtoMapper.ToSignalRPayload(notification, display);
                        await _hubContext.Clients.Group($"user_{notification.TargetUserId.Value}")
                            .SendAsync("NewNotification", dto);
                    }
                    catch (Exception perUserEx)
                    {
                        // Don't let one failed user-push abort the rest of the batch.
                        _logger.LogError(perUserEx,
                            "Failed to push notification {NotificationId} to user {UserId}; row persisted in DB",
                            notification.Id, notification.TargetUserId.Value);
                    }
                }
            }

            // FCM per user so each device gets the correct notificationId in data payload.
            foreach (var notification in notifications)
            {
                if (!notification.TargetUserId.HasValue) continue;
                try
                {
                    var display = BuildPushDisplay(notification, senderNames);
                    await _push.PushToUserAsync(
                        notification.TargetUserId.Value,
                        display.Title,
                        display.Body,
                        relatedUrl,
                        NotificationDtoMapper.ToFcmData(notification, display: display),
                        androidTag: notification.CategoryCode ?? "sbox_hrm");
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex,
                        "FCM push failed for batch notification {NotificationId} user {UserId}",
                        notification.Id, notification.TargetUserId.Value);
                }
            }

            _logger.LogInformation("📢 Batch created and sent {Count} notifications: {Title}", notifications.Count, title);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to batch create and send notifications");
        }
    }

    private async Task<bool> IsCategoryDisabledForUserAsync(Guid userId, string categoryCode, Guid? storeId)
    {
        var normalized = NotificationCategoryCodes.Normalize(categoryCode);
        if (normalized == null) return false;

        var pref = await _preferenceRepository.GetSingleAsync(
            p => p.UserId == userId
                 && p.CategoryCode == normalized
                 && (p.StoreId == null || p.StoreId == storeId));
        return pref is { IsEnabled: false };
    }

    private async Task<HashSet<Guid>> GetDisabledUserIdsAsync(
        IList<Guid> userIds, string categoryCode, Guid? storeId)
    {
        var normalized = NotificationCategoryCodes.Normalize(categoryCode);
        if (normalized == null || userIds.Count == 0) return new HashSet<Guid>();

        var disabledPrefs = await _preferenceRepository.GetAllAsync(
            p => userIds.Contains(p.UserId)
                 && p.CategoryCode == normalized
                 && !p.IsEnabled
                 && (p.StoreId == null || p.StoreId == storeId));
        return disabledPrefs.Select(p => p.UserId).ToHashSet();
    }

    private async Task<NotificationPushDisplay> BuildPushDisplayAsync(Notification notification)
    {
        var senderNames = await ResolveSenderNamesAsync(
            notification.FromUserId.HasValue
                ? new[] { notification.FromUserId }
                : Array.Empty<Guid?>());
        return BuildPushDisplay(notification, senderNames);
    }

    private static NotificationPushDisplay BuildPushDisplay(
        Notification notification,
        IReadOnlyDictionary<Guid, string> senderNames)
    {
        string? senderName = null;
        if (notification.FromUserId.HasValue
            && senderNames.TryGetValue(notification.FromUserId.Value, out var resolved)
            && !string.IsNullOrWhiteSpace(resolved))
        {
            senderName = resolved;
        }

        return NotificationPushFormatter.Format(notification, senderName);
    }

    private async Task<Dictionary<Guid, string>> ResolveSenderNamesAsync(
        IEnumerable<Guid?> userIds)
    {
        var ids = userIds
            .Where(id => id.HasValue)
            .Select(id => id!.Value)
            .Distinct()
            .ToList();
        if (ids.Count == 0) return new Dictionary<Guid, string>();

        var users = await _dbContext.Users
            .AsNoTracking()
            .Where(u => ids.Contains(u.Id))
            .Select(u => new { u.Id, u.LastName, u.FirstName, u.UserName, u.Email })
            .ToListAsync();

        return users.ToDictionary(
            u => u.Id,
            u => NotificationPushFormatter.FormatUserDisplayName(
                u.LastName, u.FirstName, u.UserName, u.Email));
    }
}

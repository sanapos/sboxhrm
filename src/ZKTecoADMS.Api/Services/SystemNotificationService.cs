using Microsoft.AspNetCore.SignalR;
using ZKTecoADMS.Api.Hubs;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Domain.Repositories;

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
    private readonly ZKTecoADMS.Infrastructure.Services.Push.IPushNotificationService _push;

    public SystemNotificationService(
        IHubContext<AttendanceHub> hubContext,
        ILogger<SystemNotificationService> logger,
        IRepository<Notification> notificationRepository,
        IRepository<NotificationPreference> preferenceRepository,
        ZKTecoADMS.Infrastructure.Services.Push.IPushNotificationService push)
    {
        _hubContext = hubContext;
        _logger = logger;
        _notificationRepository = notificationRepository;
        _preferenceRepository = preferenceRepository;
        _push = push;
    }

    public async Task SendToUserAsync(Guid userId, Notification notification)
    {
        try
        {
            var dto = MapToDto(notification);
            await _hubContext.Clients.Group($"user_{userId}").SendAsync("NewNotification", dto);
            _logger.LogInformation("📢 Sent notification to user {UserId}: {Title}", userId, notification.Title);
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
            await _push.PushToUserAsync(userId, notification.Title ?? string.Empty, notification.Message,
                notification.RelatedUrl,
                new Dictionary<string, string>
                {
                    ["notificationId"] = notification.Id.ToString(),
                    ["type"] = notification.Type.ToString(),
                });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "FCM push failed for notification {NotificationId}", notification.Id);
        }
    }

    public async Task SendToUsersAsync(IEnumerable<Guid> userIds, Notification notification)
    {
        var idList = userIds as IList<Guid> ?? userIds.ToList();
        try
        {
            var dto = MapToDto(notification);
            var groupNames = idList.Select(id => $"user_{id}").ToList();
            await _hubContext.Clients.Groups(groupNames).SendAsync("NewNotification", dto);
            _logger.LogInformation("📢 Sent notification to {Count} users: {Title}", groupNames.Count, notification.Title);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to send notification to multiple users");
        }

        try
        {
            await _push.PushToUsersAsync(idList, notification.Title ?? string.Empty, notification.Message,
                notification.RelatedUrl,
                new Dictionary<string, string>
                {
                    ["notificationId"] = notification.Id.ToString(),
                    ["type"] = notification.Type.ToString(),
                });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "FCM bulk push failed for notification {NotificationId}", notification.Id);
        }
    }

    public async Task SendToAllAsync(Notification notification)
    {
        try
        {
            var dto = MapToDto(notification);
            await _hubContext.Clients.All.SendAsync("NewNotification", dto);
            _logger.LogInformation("📢 Broadcast notification to all clients: {Title}", notification.Title);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to broadcast notification");
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
                var pref = await _preferenceRepository.GetSingleAsync(
                    p => p.UserId == targetUserId.Value && p.CategoryCode == categoryCode
                         && (p.StoreId == null || p.StoreId == storeId));
                if (pref != null && !pref.IsEnabled)
                {
                    _logger.LogInformation(
                        "Notification skipped: user {UserId} disabled category {Category} in store {StoreId}",
                        targetUserId.Value, categoryCode, storeId);
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
                CategoryCode = categoryCode,
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
            var disabledUserIds = new HashSet<Guid>();
            if (!string.IsNullOrEmpty(categoryCode))
            {
                var disabledPrefs = await _preferenceRepository.GetAllAsync(
                    p => userIdList.Contains(p.UserId) && p.CategoryCode == categoryCode && !p.IsEnabled);
                disabledUserIds = disabledPrefs.Select(p => p.UserId).ToHashSet();
            }

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
                    CategoryCode = categoryCode,
                    StoreId = storeId
                });
            }

            if (notifications.Count == 0) return;

            // Batch save all notifications BEFORE pushing via SignalR. The DB row
            // is the source of truth; any push that fails after this point can be
            // recovered by the client via /api/notifications.
            await _notificationRepository.AddRangeAsync(notifications);

            // Send individual notification DTOs to each user's group
            // Each user should receive their own notification with correct userId
            foreach (var notification in notifications)
            {
                if (notification.TargetUserId.HasValue)
                {
                    try
                    {
                        var dto = MapToDto(notification);
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

            _logger.LogInformation("📢 Batch created and sent {Count} notifications: {Title}", notifications.Count, title);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to batch create and send notifications");
        }
    }

    private static object MapToDto(Notification notification)
    {
        return new
        {
            id = notification.Id.ToString(),
            userId = notification.TargetUserId?.ToString() ?? "",
            title = notification.Title ?? "",
            message = notification.Message ?? "",
            type = (int)notification.Type,
            isRead = notification.IsRead,
            readAt = notification.ReadAt?.ToString("O"),
            actionUrl = notification.RelatedUrl,
            relatedEntityId = notification.RelatedEntityId?.ToString(),
            relatedEntityType = notification.RelatedEntityType,
            categoryCode = notification.CategoryCode ?? "",
            createdAt = notification.Timestamp.ToString("O")
        };
    }
}

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

    public SystemNotificationService(
        IHubContext<AttendanceHub> hubContext,
        ILogger<SystemNotificationService> logger,
        IRepository<Notification> notificationRepository,
        IRepository<NotificationPreference> preferenceRepository)
    {
        _hubContext = hubContext;
        _logger = logger;
        _notificationRepository = notificationRepository;
        _preferenceRepository = preferenceRepository;
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
            _logger.LogError(ex, "Failed to send notification to user {UserId}", userId);
        }
    }

    public async Task SendToUsersAsync(IEnumerable<Guid> userIds, Notification notification)
    {
        try
        {
            var dto = MapToDto(notification);
            var groupNames = userIds.Select(id => $"user_{id}").ToList();
            await _hubContext.Clients.Groups(groupNames).SendAsync("NewNotification", dto);
            _logger.LogInformation("📢 Sent notification to {Count} users: {Title}", groupNames.Count, notification.Title);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to send notification to multiple users");
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
            // Check user notification preference if categoryCode is provided
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

            // Save to database
            await _notificationRepository.AddAsync(notification);
            
            // Send via SignalR
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

            // Batch save all notifications
            await _notificationRepository.AddRangeAsync(notifications);

            // Send individual notification DTOs to each user's group
            // Each user should receive their own notification with correct userId
            foreach (var notification in notifications)
            {
                if (notification.TargetUserId.HasValue)
                {
                    var dto = MapToDto(notification);
                    await _hubContext.Clients.Group($"user_{notification.TargetUserId.Value}").SendAsync("NewNotification", dto);
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

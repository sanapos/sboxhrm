using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Interfaces;

/// <summary>
/// Interface for sending real-time system notifications via SignalR
/// </summary>
public interface ISystemNotificationService
{
    /// <summary>
    /// Send a notification to a specific user
    /// </summary>
    Task SendToUserAsync(Guid userId, Notification notification);
    
    /// <summary>
    /// Send a notification to multiple users
    /// </summary>
    Task SendToUsersAsync(IEnumerable<Guid> userIds, Notification notification);
    
    /// <summary>
    /// Send a notification to all connected clients
    /// </summary>
    Task SendToAllAsync(Notification notification);
    
    /// <summary>
    /// Create and send a notification
    /// </summary>
    Task CreateAndSendAsync(
        Guid? targetUserId,
        NotificationType type,
        string title,
        string message,
        string? relatedUrl = null,
        Guid? relatedEntityId = null,
        string? relatedEntityType = null,
        Guid? fromUserId = null,
        string? categoryCode = null,
        Guid? storeId = null);

    /// <summary>
    /// Create and send a notification to multiple users in batch
    /// </summary>
    Task CreateAndSendToUsersAsync(
        IEnumerable<Guid> targetUserIds,
        NotificationType type,
        string title,
        string message,
        string? relatedUrl = null,
        Guid? relatedEntityId = null,
        string? relatedEntityType = null,
        Guid? fromUserId = null,
        string? categoryCode = null,
        Guid? storeId = null);
}

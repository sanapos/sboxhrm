using ZKTecoADMS.Application.Notifications;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Single source of truth for shaping a Notification entity into the JSON payload
/// pushed to clients via SignalR.
///
/// Historically each notification-producing service emitted its own anonymous
/// object with subtly different field names (`createdAt` vs `timestamp`,
/// `actionUrl` vs `relatedUrl`, missing `userId`/`readAt`, etc.), forcing the
/// Flutter client to maintain brittle fallbacks. Funnel everything through here
/// so the wire schema is stable.
/// </summary>
public static class NotificationDtoMapper
{
    /// <summary>
    /// Build the payload object that goes onto the SignalR "NewNotification" event.
    /// All field names use camelCase to match the SignalR JSON protocol configured
    /// in <c>DependencyInjectionExtensions.AddApi</c>.
    /// </summary>
    public static object ToSignalRPayload(
        Notification notification,
        NotificationPushDisplay? display = null)
    {
        display ??= NotificationPushFormatter.Format(notification);
        return new
        {
            id = notification.Id.ToString(),
            userId = notification.TargetUserId?.ToString() ?? string.Empty,
            title = notification.Title ?? string.Empty,
            message = notification.Message ?? string.Empty,
            displayTitle = display.Title,
            displayBody = display.Body,
            fromUserName = display.SenderName ?? string.Empty,
            categoryLabel = display.CategoryLabel,
            type = (int)notification.Type,
            isRead = notification.IsRead,
            readAt = notification.ReadAt?.ToString("O"),
            actionUrl = notification.RelatedUrl,
            relatedUrl = notification.RelatedUrl, // legacy alias (some old clients read this)
            relatedEntityId = notification.RelatedEntityId?.ToString(),
            relatedEntityType = notification.RelatedEntityType,
            categoryCode = notification.CategoryCode ?? string.Empty,
            createdAt = notification.Timestamp.ToString("O"),
            timestamp = notification.Timestamp.ToString("O"), // legacy alias
            storeId = notification.StoreId?.ToString(),
        };
    }

    /// <summary>
    /// Common FCM data dictionary. <paramref name="extra"/> entries take precedence.
    /// </summary>
    public static IDictionary<string, string> ToFcmData(
        Notification notification,
        IDictionary<string, string>? extra = null,
        NotificationPushDisplay? display = null)
    {
        display ??= NotificationPushFormatter.Format(notification);
        var data = new Dictionary<string, string>
        {
            ["notificationId"] = notification.Id.ToString(),
            // Severity (Info, Warning, …) — NOT used for screen routing on mobile.
            ["notificationType"] = notification.Type.ToString(),
            ["title"] = display.Title,
            ["message"] = display.Body,
            ["displayTitle"] = display.Title,
            ["displayBody"] = display.Body,
            ["categoryLabel"] = display.CategoryLabel,
        };
        if (!string.IsNullOrEmpty(display.SenderName))
            data["fromUserName"] = display.SenderName!;
        if (!string.IsNullOrEmpty(notification.CategoryCode))
            data["categoryCode"] = notification.CategoryCode!;
        if (!string.IsNullOrEmpty(notification.RelatedEntityType))
            data["relatedEntityType"] = notification.RelatedEntityType!;
        if (notification.RelatedEntityId.HasValue)
            data["relatedEntityId"] = notification.RelatedEntityId.Value.ToString();
        if (!string.IsNullOrEmpty(notification.RelatedUrl))
            data["actionUrl"] = notification.RelatedUrl!;

        if (extra != null)
        {
            foreach (var kv in extra)
                data[kv.Key] = kv.Value;
        }
        return data;
    }
}

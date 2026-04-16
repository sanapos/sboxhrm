using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.DTOs.Notifications;

public class NotificationDto
{
    public Guid Id { get; set; }
    public Guid? TargetUserId { get; set; }
    public string? TargetUserName { get; set; }
    public NotificationType Type { get; set; }
    public string? Title { get; set; }
    public string Message { get; set; } = string.Empty;
    public DateTime Timestamp { get; set; }
    public bool IsRead { get; set; }
    public DateTime? ReadAt { get; set; }
    public Guid? FromUserId { get; set; }
    public string? RelatedUrl { get; set; }
    public Guid? RelatedEntityId { get; set; }
    public string? RelatedEntityType { get; set; }
    public string? CategoryCode { get; set; }
}

public class CreateNotificationDto
{
    public Guid? TargetUserId { get; set; }
    public NotificationType Type { get; set; }
    public string? Title { get; set; }
    public string Message { get; set; } = string.Empty;
    public string? RelatedUrl { get; set; }
    public Guid? RelatedEntityId { get; set; }
    public string? RelatedEntityType { get; set; }
    public string? CategoryCode { get; set; }
}

public class BulkCreateNotificationDto
{
    public List<Guid> TargetUserIds { get; set; } = new();
    public NotificationType Type { get; set; }
    public string? Title { get; set; }
    public string Message { get; set; } = string.Empty;
    public string? RelatedUrl { get; set; }
}

public class NotificationQueryParams
{
    public int Page { get; set; } = 1;
    public int PageSize { get; set; } = 20;
    public bool? IsRead { get; set; }
    public NotificationType? Type { get; set; }
}

public class NotificationSummaryDto
{
    public int TotalCount { get; set; }
    public int UnreadCount { get; set; }
    public List<NotificationDto> RecentNotifications { get; set; } = new();
}

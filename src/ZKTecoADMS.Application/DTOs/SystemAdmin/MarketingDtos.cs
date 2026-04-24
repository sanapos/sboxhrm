using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.DTOs.SystemAdmin;

public class NotificationTemplateDto
{
    public Guid Id { get; set; }
    public string Code { get; set; } = string.Empty;
    public string Title { get; set; } = string.Empty;
    public string Body { get; set; } = string.Empty;
    public List<string>? Variables { get; set; }
    public NotificationChannel Channels { get; set; }
    public string Locale { get; set; } = "vi-VN";
    public bool IsActive { get; set; }
    public DateTime CreatedAt { get; set; }
}

public class CreateNotificationTemplateDto
{
    public string Code { get; set; } = string.Empty;
    public string Title { get; set; } = string.Empty;
    public string Body { get; set; } = string.Empty;
    public List<string>? Variables { get; set; }
    public NotificationChannel Channels { get; set; } = NotificationChannel.InApp | NotificationChannel.Banner;
    public string Locale { get; set; } = "vi-VN";
    public bool IsActive { get; set; } = true;
}

public class MarketingCampaignDto
{
    public Guid Id { get; set; }
    public string Name { get; set; } = string.Empty;
    public string? Description { get; set; }
    public Guid? TemplateId { get; set; }
    public NotificationChannel Channels { get; set; }
    public DateTime? ScheduleAt { get; set; }
    public CampaignStatus Status { get; set; }
    public Guid? AnnouncementId { get; set; }
    public int RecipientCount { get; set; }
    public int DeliveredCount { get; set; }
    public int OpenedCount { get; set; }
    public int ClickedCount { get; set; }
    public DateTime? LaunchedAt { get; set; }
    public DateTime CreatedAt { get; set; }
}

public class CreateMarketingCampaignDto
{
    public string Name { get; set; } = string.Empty;
    public string? Description { get; set; }
    public Guid? TemplateId { get; set; }
    /// <summary>Nếu null sẽ dùng nội dung từ template.</summary>
    public string? CustomTitle { get; set; }
    public string? CustomBody { get; set; }
    /// <summary>Biến mailmerge bổ sung khi không dùng template.</summary>
    public Dictionary<string, string>? Variables { get; set; }
    public AudienceSpec? Audience { get; set; }
    public NotificationChannel Channels { get; set; } = NotificationChannel.InApp | NotificationChannel.Banner;
    public DateTime? ScheduleAt { get; set; }
    public bool LaunchNow { get; set; }
}

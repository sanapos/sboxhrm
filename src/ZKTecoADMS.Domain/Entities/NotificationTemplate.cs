using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Mẫu thông báo có thể tái sử dụng cho campaign / system announcement.
/// Hỗ trợ mailmerge bằng placeholder dạng <c>{storeName}</c>, <c>{daysLeft}</c>...
/// </summary>
public class NotificationTemplate : Entity<Guid>
{
    [Required, MaxLength(100)]
    public string Code { get; set; } = string.Empty;

    [Required, MaxLength(200)]
    public string Title { get; set; } = string.Empty;

    [Required]
    public string Body { get; set; } = string.Empty;

    /// <summary>JSON list các biến mẫu (vd: ["storeName","daysLeft","renewalUrl"]).</summary>
    public string? VariablesJson { get; set; }

    public NotificationChannel Channels { get; set; } = NotificationChannel.InApp;

    [MaxLength(10)]
    public string Locale { get; set; } = "vi-VN";

    public bool IsActive { get; set; } = true;
}

/// <summary>
/// Marketing campaign – wrapper cao cấp quanh SystemAnnouncement: cho phép schedule, A/B test (thì ở P4),
/// thống kê chi tiết. Mỗi campaign khi "Launch" sẽ tạo ra 1+ SystemAnnouncement.
/// </summary>
public class MarketingCampaign : Entity<Guid>
{
    [Required, MaxLength(200)]
    public string Name { get; set; } = string.Empty;

    public string? Description { get; set; }

    /// <summary>FK NotificationTemplate (nullable: có thể tự nhập nội dung tự do).</summary>
    public Guid? TemplateId { get; set; }
    public NotificationTemplate? Template { get; set; }

    /// <summary>JSON AudienceSpec.</summary>
    public string AudienceJson { get; set; } = "{}";

    public NotificationChannel Channels { get; set; } = NotificationChannel.InApp | NotificationChannel.Banner;

    public DateTime? ScheduleAt { get; set; }

    public CampaignStatus Status { get; set; } = CampaignStatus.Draft;

    public Guid? AnnouncementId { get; set; }

    /// <summary>Stats snapshot (cập nhật từ AnnouncementService).</summary>
    public int RecipientCount { get; set; }
    public int DeliveredCount { get; set; }
    public int OpenedCount { get; set; }
    public int ClickedCount { get; set; }

    public Guid CreatedByUserId { get; set; }
    public DateTime? LaunchedAt { get; set; }
}

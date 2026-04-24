using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.DTOs.SystemAdmin;

/// <summary>
/// Đặc tả audience của 1 announcement / campaign.
/// Áp dụng theo phép giao (AND) giữa các filter có giá trị; trong cùng 1 filter là OR.
/// Nếu tất cả null/empty và <see cref="AllUsers"/>=true ⇒ broadcast toàn hệ thống.
/// </summary>
public class AudienceSpec
{
    public bool AllUsers { get; set; }
    public List<string>? Roles { get; set; }
    public List<Guid>? StoreIds { get; set; }
    public List<Guid>? PackageIds { get; set; }
    public List<Guid>? AgentIds { get; set; }
    /// <summary>"expired" | "expiring_soon" | "active"</summary>
    public string? LicenseStatus { get; set; }
    /// <summary>Lọc thêm user chưa login từ trước ngày này</summary>
    public DateTime? LastLoginBefore { get; set; }
    /// <summary>Loại trừ user cụ thể</summary>
    public List<Guid>? ExcludeUserIds { get; set; }
}

public class SystemAnnouncementDto
{
    public Guid Id { get; set; }
    public string Title { get; set; } = string.Empty;
    public string Content { get; set; } = string.Empty;
    public AnnouncementKind Kind { get; set; }
    public AnnouncementSeverity Severity { get; set; }
    public AnnouncementStatus Status { get; set; }
    public NotificationChannel Channels { get; set; }
    public AudienceSpec Audience { get; set; } = new();
    public DateTime? ScheduleAt { get; set; }
    public DateTime? ExpiresAt { get; set; }
    public bool RequireAck { get; set; }
    public bool AllowDismiss { get; set; }
    public string? ImageUrl { get; set; }
    public string? ActionUrl { get; set; }
    public string? ActionLabel { get; set; }
    public int RecipientCount { get; set; }
    public int DeliveredCount { get; set; }
    public int SeenCount { get; set; }
    public int ClickedCount { get; set; }
    public int AckedCount { get; set; }
    public DateTime? SentAt { get; set; }
    public DateTime CreatedAt { get; set; }
    public string? CreatedBy { get; set; }
}

public class CreateSystemAnnouncementDto
{
    public string Title { get; set; } = string.Empty;
    public string Content { get; set; } = string.Empty;
    public AnnouncementKind Kind { get; set; } = AnnouncementKind.News;
    public AnnouncementSeverity Severity { get; set; } = AnnouncementSeverity.Info;
    public NotificationChannel Channels { get; set; } = NotificationChannel.InApp | NotificationChannel.Banner;
    public AudienceSpec Audience { get; set; } = new() { AllUsers = true };
    public DateTime? ScheduleAt { get; set; }
    public DateTime? ExpiresAt { get; set; }
    public bool RequireAck { get; set; }
    public bool AllowDismiss { get; set; } = true;
    public string? ImageUrl { get; set; }
    public string? ActionUrl { get; set; }
    public string? ActionLabel { get; set; }

    /// <summary>true ⇒ tạo & gửi luôn. false ⇒ chỉ lưu Draft / Scheduled</summary>
    public bool SendNow { get; set; } = true;
}

public class AudiencePreviewDto
{
    public int TotalUsers { get; set; }
    public int TotalStores { get; set; }
    public Dictionary<string, int> ByRole { get; set; } = new();
}

public class AnnouncementStatsDto
{
    public Guid AnnouncementId { get; set; }
    public int Recipients { get; set; }
    public int Delivered { get; set; }
    public int Seen { get; set; }
    public int Clicked { get; set; }
    public int Acked { get; set; }
    public int Dismissed { get; set; }
    public int Failed { get; set; }
    public Dictionary<string, int> ByChannel { get; set; } = new();
}

public class ActiveAnnouncementDto
{
    public Guid Id { get; set; }
    public string Title { get; set; } = string.Empty;
    public string Content { get; set; } = string.Empty;
    public AnnouncementKind Kind { get; set; }
    public AnnouncementSeverity Severity { get; set; }
    public bool RequireAck { get; set; }
    public bool AllowDismiss { get; set; }
    public string? ImageUrl { get; set; }
    public string? ActionUrl { get; set; }
    public string? ActionLabel { get; set; }
    public DateTime? ExpiresAt { get; set; }
    public bool IsSeen { get; set; }
    public bool IsAcked { get; set; }
    public bool IsDismissed { get; set; }
}

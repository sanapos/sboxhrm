using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Thông báo hệ thống cấp SuperAdmin: bảo trì / nâng cấp / nhắc gia hạn / marketing.
/// Khác với <see cref="Notification"/> (thông báo cá nhân) – đây là campaign có audience rule,
/// được fan-out tới nhiều user qua <see cref="AnnouncementDelivery"/>.
/// </summary>
public class SystemAnnouncement : Entity<Guid>
{
    [Required]
    [MaxLength(200)]
    public string Title { get; set; } = string.Empty;

    /// <summary>Nội dung (markdown / html)</summary>
    [Required]
    public string Content { get; set; } = string.Empty;

    public AnnouncementKind Kind { get; set; } = AnnouncementKind.News;

    public AnnouncementSeverity Severity { get; set; } = AnnouncementSeverity.Info;

    public AnnouncementStatus Status { get; set; } = AnnouncementStatus.Draft;

    /// <summary>Bitwise flags – kênh phát (InApp|Banner|Email|Sms|Push)</summary>
    public NotificationChannel Channels { get; set; } = NotificationChannel.InApp | NotificationChannel.Banner;

    /// <summary>JSON đặc tả audience – xem AudienceSpec DTO ở Application layer.</summary>
    public string AudienceJson { get; set; } = "{}";

    /// <summary>Thời điểm phát hành (null = phát ngay khi gửi)</summary>
    public DateTime? ScheduleAt { get; set; }

    /// <summary>Thời điểm hết hiệu lực hiển thị banner</summary>
    public DateTime? ExpiresAt { get; set; }

    /// <summary>Yêu cầu user xác nhận đã đọc (popup chặn UI cho thông báo bảo trì quan trọng)</summary>
    public bool RequireAck { get; set; }

    /// <summary>Cho phép user dismiss banner</summary>
    public bool AllowDismiss { get; set; } = true;

    [MaxLength(500)]
    public string? ImageUrl { get; set; }

    [MaxLength(500)]
    public string? ActionUrl { get; set; }

    [MaxLength(100)]
    public string? ActionLabel { get; set; }

    /// <summary>Tổng số người nhận sau khi resolve audience</summary>
    public int RecipientCount { get; set; }

    public int DeliveredCount { get; set; }
    public int SeenCount { get; set; }
    public int ClickedCount { get; set; }
    public int AckedCount { get; set; }

    public DateTime? SentAt { get; set; }

    public virtual ICollection<AnnouncementDelivery> Deliveries { get; set; } = new List<AnnouncementDelivery>();
}

/// <summary>
/// Bản ghi delivery cho từng người nhận của 1 SystemAnnouncement (per-user, per-channel).
/// </summary>
public class AnnouncementDelivery : Entity<Guid>
{
    public Guid AnnouncementId { get; set; }
    public virtual SystemAnnouncement? Announcement { get; set; }

    public Guid UserId { get; set; }
    public virtual ApplicationUser? User { get; set; }

    public Guid? StoreId { get; set; }
    public virtual Store? Store { get; set; }

    public NotificationChannel Channel { get; set; } = NotificationChannel.InApp;

    public DeliveryStatus Status { get; set; } = DeliveryStatus.Pending;

    public DateTime? DeliveredAt { get; set; }
    public DateTime? SeenAt { get; set; }
    public DateTime? ClickedAt { get; set; }
    public DateTime? AckedAt { get; set; }
    public DateTime? DismissedAt { get; set; }

    [MaxLength(500)]
    public string? ErrorMessage { get; set; }
}

using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Thông báo - Notification
/// </summary>
public class Notification : Entity<Guid>
{
    /// <summary>
    /// Người nhận (null = tất cả)
    /// </summary>
    public Guid? TargetUserId { get; set; }

    /// <summary>
    /// Loại thông báo
    /// </summary>
    [Required]
    public NotificationType Type { get; set; } = NotificationType.Info;

    /// <summary>
    /// Tiêu đề
    /// </summary>
    [MaxLength(200)]
    public string? Title { get; set; }

    /// <summary>
    /// Nội dung thông báo
    /// </summary>
    [Required]
    [MaxLength(2000)]
    public string Message { get; set; } = string.Empty;

    /// <summary>
    /// Thời gian tạo
    /// </summary>
    [Required]
    public DateTime Timestamp { get; set; } = DateTime.UtcNow;

    /// <summary>
    /// Đã đọc chưa
    /// </summary>
    public bool IsRead { get; set; } = false;

    /// <summary>
    /// Thời gian đọc
    /// </summary>
    public DateTime? ReadAt { get; set; }

    /// <summary>
    /// Người gửi (null = hệ thống)
    /// </summary>
    public Guid? FromUserId { get; set; }

    /// <summary>
    /// Link liên quan (nếu có)
    /// </summary>
    [MaxLength(500)]
    public string? RelatedUrl { get; set; }

    /// <summary>
    /// ID đối tượng liên quan (ví dụ: LeaveId, RequestId...)
    /// </summary>
    public Guid? RelatedEntityId { get; set; }

    /// <summary>
    /// Loại đối tượng liên quan
    /// </summary>
    [MaxLength(100)]
    public string? RelatedEntityType { get; set; }
    
    /// <summary>
    /// Mã nhóm thông báo (tham chiếu NotificationCategory.Code)
    /// </summary>
    [MaxLength(50)]
    public string? CategoryCode { get; set; }

    /// <summary>
    /// Cửa hàng liên quan (null = thông báo hệ thống)
    /// </summary>
    public Guid? StoreId { get; set; }
    public virtual Store? Store { get; set; }

    // Navigation Properties
    public virtual ApplicationUser? TargetUser { get; set; }
    public virtual ApplicationUser? FromUser { get; set; }
}

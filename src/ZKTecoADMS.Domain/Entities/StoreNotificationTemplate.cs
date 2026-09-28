using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Mẫu thông báo của cửa hàng — quản lý soạn sẵn để gửi nhanh cho nhân viên
/// (có biến {ten}, {cuahang}, {ngay}, {gio}…).
/// </summary>
public class StoreNotificationTemplate
{
    [Key]
    public Guid Id { get; set; }

    public Guid StoreId { get; set; }

    [MaxLength(120)]
    public string Name { get; set; } = string.Empty;

    [MaxLength(200)]
    public string Title { get; set; } = string.Empty;

    [MaxLength(2000)]
    public string Body { get; set; } = string.Empty;

    [MaxLength(50)]
    public string CategoryCode { get; set; } = "internal_comm";

    public NotificationType Type { get; set; } = NotificationType.Info;

    public int UsageCount { get; set; }

    public DateTime? LastUsedAt { get; set; }

    public Guid? CreatedByUserId { get; set; }

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public bool IsActive { get; set; } = true;
}

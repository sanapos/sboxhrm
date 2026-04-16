using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Nhóm thông báo - Notification Category
/// </summary>
public class NotificationCategory : Entity<Guid>
{
    /// <summary>
    /// Mã nhóm (unique, ví dụ: attendance, leave, overtime...)
    /// </summary>
    [Required]
    [MaxLength(50)]
    public string Code { get; set; } = string.Empty;

    /// <summary>
    /// Tên hiển thị
    /// </summary>
    [Required]
    [MaxLength(100)]
    public string DisplayName { get; set; } = string.Empty;

    /// <summary>
    /// Mô tả
    /// </summary>
    [MaxLength(255)]
    public string? Description { get; set; }

    /// <summary>
    /// Icon name (Material Icons)
    /// </summary>
    [MaxLength(50)]
    public string? Icon { get; set; }

    /// <summary>
    /// Thứ tự hiển thị
    /// </summary>
    public int DisplayOrder { get; set; }

    /// <summary>
    /// Nhóm hệ thống (không cho xóa/sửa)
    /// </summary>
    public bool IsSystem { get; set; } = true;

    /// <summary>
    /// Mặc định bật thông báo
    /// </summary>
    public bool DefaultEnabled { get; set; } = true;

    /// <summary>
    /// Cửa hàng (null = dùng chung)
    /// </summary>
    public Guid? StoreId { get; set; }
    public virtual Store? Store { get; set; }
}

using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Thiết lập nhận thông báo của người dùng - Notification Preference
/// </summary>
public class NotificationPreference : Entity<Guid>
{
    /// <summary>
    /// Người dùng
    /// </summary>
    public Guid UserId { get; set; }

    /// <summary>
    /// Mã nhóm thông báo (tham chiếu NotificationCategory.Code)
    /// </summary>
    [Required]
    [MaxLength(50)]
    public string CategoryCode { get; set; } = string.Empty;

    /// <summary>
    /// Bật/tắt nhận thông báo cho nhóm này
    /// </summary>
    public bool IsEnabled { get; set; } = true;

    /// <summary>
    /// Cửa hàng
    /// </summary>
    public Guid? StoreId { get; set; }
    public virtual Store? Store { get; set; }

    /// <summary>
    /// Navigation
    /// </summary>
    public virtual ApplicationUser? User { get; set; }
}

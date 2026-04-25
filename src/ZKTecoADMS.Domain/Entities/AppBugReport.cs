using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Báo lỗi & Góp ý từ màn hình Cài đặt ứng dụng.
/// Không gắn với Store cụ thể — SuperAdmin xem toàn bộ.
/// </summary>
public class AppBugReport : Entity<Guid>
{
    /// <summary>UserId người gửi (nullable nếu chưa đăng nhập)</summary>
    [MaxLength(100)]
    public string? UserId { get; set; }

    [MaxLength(200)]
    public string? UserName { get; set; }

    [MaxLength(100)]
    public string? UserEmail { get; set; }

    /// <summary>Tên cửa hàng (nếu có)</summary>
    [MaxLength(200)]
    public string? StoreName { get; set; }

    /// <summary>Loại: Bug | Suggestion | Other</summary>
    [Required]
    [MaxLength(30)]
    public string Type { get; set; } = "Bug";

    [Required]
    [MaxLength(300)]
    public string Title { get; set; } = string.Empty;

    [Required]
    [MaxLength(5000)]
    public string Content { get; set; } = string.Empty;

    /// <summary>Phiên bản ứng dụng</summary>
    [MaxLength(50)]
    public string? AppVersion { get; set; }

    /// <summary>Thông tin thiết bị</summary>
    [MaxLength(200)]
    public string? DeviceInfo { get; set; }

    /// <summary>Trạng thái xử lý: New | InProgress | Resolved | Closed</summary>
    [Required]
    [MaxLength(30)]
    public string Status { get; set; } = "New";

    /// <summary>Ghi chú xử lý từ SuperAdmin</summary>
    [MaxLength(2000)]
    public string? AdminNote { get; set; }

    public DateTime? ResolvedAt { get; set; }
}

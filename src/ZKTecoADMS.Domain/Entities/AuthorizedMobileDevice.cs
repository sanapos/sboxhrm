using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Authorized mobile device for mobile attendance.
/// </summary>
public class AuthorizedMobileDevice : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    [Required]
    [MaxLength(200)]
    public string DeviceId { get; set; } = string.Empty;

    [Required]
    [MaxLength(200)]
    public string DeviceName { get; set; } = string.Empty;

    [Required]
    [MaxLength(200)]
    public string DeviceModel { get; set; } = string.Empty;

    [MaxLength(50)]
    public string? OsVersion { get; set; }

    [MaxLength(100)]
    public string? EmployeeId { get; set; }

    [MaxLength(200)]
    public string? EmployeeName { get; set; }

    public bool IsAuthorized { get; set; } = true;

    public bool CanUseFaceId { get; set; } = true;

    public bool CanUseGps { get; set; } = true;

    /// <summary>
    /// Cho phép thiết bị chấm công ngoài công ty (bỏ qua GPS và WiFi).
    /// </summary>
    public bool AllowOutsideCheckIn { get; set; } = false;

    /// <summary>
    /// Cho phép chấm công đi đường (Bắt đầu đi / Đến điểm làm) — tính giờ lương thường, không tăng ca.
    /// </summary>
    public bool AllowTravelCheckIn { get; set; } = false;

    /// <summary>
    /// Bắt chụp ảnh hiện trường sau khi chấm công (cần bật RequirePhotoProof ở cài đặt cửa hàng).
    /// </summary>
    public bool RequirePhotoProof { get; set; } = false;

    /// <summary>
    /// MAC address của WiFi router khi đăng ký thiết bị (BSSID).
    /// </summary>
    [MaxLength(50)]
    public string? WifiBssid { get; set; }

    public DateTime? AuthorizedAt { get; set; }

    public DateTime? LastUsedAt { get; set; }

    /// <summary>JSON mảng Guid — chi nhánh NV chọn lúc đăng ký thiết bị (chờ duyệt).</summary>
    [MaxLength(4000)]
    public string? SelectedLocationIdsJson { get; set; }
}

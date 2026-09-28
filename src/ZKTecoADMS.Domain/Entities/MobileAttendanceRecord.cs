using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Mobile attendance punch record (Face ID + GPS check-in/out).
/// </summary>
public class MobileAttendanceRecord : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    [Required]
    [MaxLength(100)]
    public string OdooEmployeeId { get; set; } = string.Empty;

    [Required]
    [MaxLength(200)]
    public string EmployeeName { get; set; } = string.Empty;

    public DateTime PunchTime { get; set; }

    /// <summary>
    /// 0: Check-in, 1: Check-out, 2: Bắt đầu đi (công tác), 3: Đến điểm làm
    /// </summary>
    public int PunchType { get; set; }

    public double? Latitude { get; set; }
    public double? Longitude { get; set; }

    [MaxLength(200)]
    public string? LocationName { get; set; }

    public double? DistanceFromLocation { get; set; }

    [MaxLength(500)]
    public string? FaceImageUrl { get; set; }

    /// <summary>Ảnh hiện trường sau chấm công (GPS + timestamp watermark).</summary>
    [MaxLength(500)]
    public string? SitePhotoUrl { get; set; }

    public double? FaceMatchScore { get; set; }

    /// <summary>
    /// face, gps, face_gps, manual
    /// </summary>
    [MaxLength(20)]
    public string VerifyMethod { get; set; } = "face_gps";

    /// <summary>
    /// pending, approved, rejected, auto_approved
    /// </summary>
    [MaxLength(20)]
    public string Status { get; set; } = "pending";

    [MaxLength(200)]
    public string? ApprovedBy { get; set; }

    public DateTime? ApprovedAt { get; set; }

    [MaxLength(500)]
    public string? RejectReason { get; set; }

    [MaxLength(200)]
    public string? DeviceId { get; set; }

    [MaxLength(200)]
    public string? DeviceName { get; set; }

    [MaxLength(500)]
    public string? Note { get; set; }

    [MaxLength(200)]
    public string? WifiSsid { get; set; }

    [MaxLength(50)]
    public string? WifiBssid { get; set; }

    [MaxLength(100)]
    public string? WifiIpAddress { get; set; }

    // ─── Duyệt chấm công v2 ───

    /// <summary>Chấm ngoài vị trí công ty (ngoài GPS/WiFi đã khai báo)</summary>
    public bool IsOutside { get; set; }

    /// <summary>Lý do nhân viên ghi khi chấm ngoài vị trí</summary>
    [MaxLength(500)]
    public string? OutsideReason { get; set; }

    /// <summary>Độ chính xác GPS (mét) do máy báo</summary>
    public double? GpsAccuracy { get; set; }

    /// <summary>Điểm rủi ro 0–100 (càng cao càng cần xem kỹ)</summary>
    public int RiskScore { get; set; }

    /// <summary>trusted / review / high</summary>
    [MaxLength(10)]
    public string? RiskLevel { get; set; }

    /// <summary>JSON mảng mô tả các dấu hiệu rủi ro</summary>
    public string? RiskFlags { get; set; }

    /// <summary>Thời điểm đã xóa ảnh bằng chứng theo hạn lưu</summary>
    public DateTime? EvidencePurgedAt { get; set; }
}

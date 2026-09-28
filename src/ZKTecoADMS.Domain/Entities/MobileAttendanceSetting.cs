using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Mobile attendance settings per store (Face ID + GPS configuration).
/// </summary>
public class MobileAttendanceSetting : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    public bool EnableFaceId { get; set; } = true;
    public bool EnableGps { get; set; } = true;
    public bool EnableWifi { get; set; }
    public bool EnableLivenessDetection { get; set; } = true;

    /// <summary>
    /// "any" = at least one enabled method must pass;
    /// "all" = all enabled methods must pass.
    /// </summary>
    public string VerificationMode { get; set; } = "all";

    public int GpsRadiusMeters { get; set; } = 100;
    public double MinFaceMatchScore { get; set; } = 80.0;

    public bool AutoApproveInRange { get; set; } = true;
    public bool AllowManualApproval { get; set; } = true;

    public int MaxPhotosPerRegistration { get; set; } = 5;
    public int MaxPunchesPerDay { get; set; } = 4;
    public bool RequirePhotoProof { get; set; }

    /// <summary>
    /// Minimum minutes between two punches from the same employee.
    /// Punches within this interval are rejected as duplicates. Default: 5 minutes.
    /// </summary>
    public int MinPunchIntervalMinutes { get; set; } = 5;

    // ─── Duyệt chấm công v2 ───

    /// <summary>Tự duyệt bản chấm ngoài vị trí được chấm điểm «tin cậy»</summary>
    public bool AutoApproveTrusted { get; set; } = true;

    /// <summary>Khoảng cách tối đa tới vị trí gần nhất để còn được xem là tin cậy (mét)</summary>
    public int TrustedMaxDistanceMeters { get; set; } = 300;

    /// <summary>Điểm khớp khuôn mặt tối thiểu để tin cậy (%)</summary>
    public double TrustedMinFaceScore { get; set; } = 85;

    /// <summary>Giữ ảnh bằng chứng sau khi duyệt (ngày), sau đó tự xóa</summary>
    public int EvidenceRetentionDays { get; set; } = 30;
}

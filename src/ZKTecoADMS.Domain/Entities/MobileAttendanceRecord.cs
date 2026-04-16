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
    /// 0: Check-in, 1: Check-out
    /// </summary>
    public int PunchType { get; set; }

    public double? Latitude { get; set; }
    public double? Longitude { get; set; }

    [MaxLength(200)]
    public string? LocationName { get; set; }

    public double? DistanceFromLocation { get; set; }

    [MaxLength(500)]
    public string? FaceImageUrl { get; set; }

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
}

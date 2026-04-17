using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Request to change mobile attendance device. Requires manager approval.
/// On approval, old device + face data are deleted and new device is registered.
/// </summary>
public class DeviceChangeRequest : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    [Required]
    [MaxLength(100)]
    public string EmployeeId { get; set; } = string.Empty;

    [MaxLength(200)]
    public string EmployeeName { get; set; } = string.Empty;

    // Old device info
    public Guid OldDeviceRecordId { get; set; }

    [MaxLength(200)]
    public string OldDeviceName { get; set; } = string.Empty;

    [MaxLength(200)]
    public string OldDeviceModel { get; set; } = string.Empty;

    // New device info
    [Required]
    [MaxLength(200)]
    public string NewDeviceId { get; set; } = string.Empty;

    [Required]
    [MaxLength(200)]
    public string NewDeviceName { get; set; } = string.Empty;

    [MaxLength(200)]
    public string NewDeviceModel { get; set; } = string.Empty;

    [MaxLength(50)]
    public string? NewOsVersion { get; set; }

    [MaxLength(50)]
    public string? NewWifiBssid { get; set; }

    /// <summary>
    /// JSON array of base64 face images for the new device registration
    /// </summary>
    public string NewFaceImagesJson { get; set; } = "[]";

    /// <summary>
    /// 0 = Pending, 1 = Approved, 2 = Rejected
    /// </summary>
    public int Status { get; set; } = 0;

    [MaxLength(500)]
    public string? Reason { get; set; }

    public DateTime RequestedAt { get; set; } = DateTime.UtcNow;

    public Guid? ApprovedBy { get; set; }

    public DateTime? ApprovedAt { get; set; }

    [MaxLength(500)]
    public string? RejectReason { get; set; }
}

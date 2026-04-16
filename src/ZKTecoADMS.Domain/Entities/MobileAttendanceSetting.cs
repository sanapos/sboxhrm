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
}

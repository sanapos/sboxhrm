using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Work location for mobile attendance check-in (Face ID + GPS).
/// </summary>
public class MobileWorkLocation : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    [Required]
    [MaxLength(200)]
    public string Name { get; set; } = string.Empty;

    [MaxLength(500)]
    public string Address { get; set; } = string.Empty;

    [Required]
    public double Latitude { get; set; }

    [Required]
    public double Longitude { get; set; }

    public int Radius { get; set; } = 100;

    public bool AutoApproveInRange { get; set; } = true;

    [MaxLength(200)]
    public string? WifiSsid { get; set; }

    [MaxLength(200)]
    public string? WifiBssid { get; set; }

    /// <summary>
    /// Comma-separated list of allowed IP addresses for WiFi verification
    /// </summary>
    [MaxLength(500)]
    public string? AllowedIpRange { get; set; }
}

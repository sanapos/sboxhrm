using System;
using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Represents a geographic fence (geofence) for location-based attendance tracking.
/// </summary>
public class Geofence : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    [Required]
    [MaxLength(200)]
    public string Name { get; set; } = string.Empty;

    [MaxLength(500)]
    public string? Description { get; set; }

    /// <summary>
    /// Latitude of the center point
    /// </summary>
    [Required]
    public double Latitude { get; set; }

    /// <summary>
    /// Longitude of the center point
    /// </summary>
    [Required]
    public double Longitude { get; set; }

    /// <summary>
    /// Radius in meters
    /// </summary>
    [Required]
    public double RadiusMeters { get; set; } = 100;

    /// <summary>
    /// Address or location name
    /// </summary>
    [MaxLength(500)]
    public string? Address { get; set; }

    /// <summary>
    /// Whether this geofence is active
    /// </summary>
    public new bool IsActive { get; set; } = true;

    /// <summary>
    /// Whether this is the primary geofence for the store
    /// </summary>
    public bool IsPrimary { get; set; }

    /// <summary>
    /// Allowed check-in time tolerance in minutes (before/after scheduled shift)
    /// </summary>
    public int CheckInToleranceMinutes { get; set; } = 15;

    /// <summary>
    /// Allowed check-out time tolerance in minutes
    /// </summary>
    public int CheckOutToleranceMinutes { get; set; } = 15;

    /// <summary>
    /// Whether to allow check-in outside of geofence with manager approval
    /// </summary>
    public bool AllowOutsideCheckIn { get; set; }
}

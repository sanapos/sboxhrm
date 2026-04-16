namespace ZKTecoADMS.Application.DTOs;

/// <summary>
/// DTO for geofence data
/// </summary>
public record GeofenceDto
{
    public Guid Id { get; init; }
    public Guid StoreId { get; init; }
    public string Name { get; init; } = string.Empty;
    public string? Description { get; init; }
    public double Latitude { get; init; }
    public double Longitude { get; init; }
    public double RadiusMeters { get; init; }
    public string? Address { get; init; }
    public bool IsActive { get; init; }
    public bool IsPrimary { get; init; }
    public int CheckInToleranceMinutes { get; init; }
    public int CheckOutToleranceMinutes { get; init; }
    public bool AllowOutsideCheckIn { get; init; }
    public DateTime CreatedAt { get; init; }
    public DateTime? UpdatedAt { get; init; }
}

/// <summary>
/// DTO for creating a new geofence
/// </summary>
public record CreateGeofenceDto
{
    public string Name { get; init; } = string.Empty;
    public string? Description { get; init; }
    public double Latitude { get; init; }
    public double Longitude { get; init; }
    public double RadiusMeters { get; init; } = 100;
    public string? Address { get; init; }
    public bool IsPrimary { get; init; }
    public int CheckInToleranceMinutes { get; init; } = 15;
    public int CheckOutToleranceMinutes { get; init; } = 15;
    public bool AllowOutsideCheckIn { get; init; }
}

/// <summary>
/// DTO for updating a geofence
/// </summary>
public record UpdateGeofenceDto
{
    public string Name { get; init; } = string.Empty;
    public string? Description { get; init; }
    public double Latitude { get; init; }
    public double Longitude { get; init; }
    public double RadiusMeters { get; init; }
    public string? Address { get; init; }
    public bool IsActive { get; init; }
    public bool IsPrimary { get; init; }
    public int CheckInToleranceMinutes { get; init; }
    public int CheckOutToleranceMinutes { get; init; }
    public bool AllowOutsideCheckIn { get; init; }
}

/// <summary>
/// DTO for validating location against geofences
/// </summary>
public record ValidateLocationDto
{
    public double Latitude { get; init; }
    public double Longitude { get; init; }
}

/// <summary>
/// DTO for location validation result
/// </summary>
public record LocationValidationResultDto
{
    public bool IsWithinGeofence { get; init; }
    public Guid? MatchedGeofenceId { get; init; }
    public string? MatchedGeofenceName { get; init; }
    public double? DistanceFromCenter { get; init; }
    public double? AllowedRadius { get; init; }
    public bool CanCheckInOutside { get; init; }
    public string? Message { get; init; }
}

/// <summary>
/// DTO for mobile check-in request
/// </summary>
public record MobileCheckInDto
{
    public double Latitude { get; init; }
    public double Longitude { get; init; }
    public string? Note { get; init; }
    public bool ForceOverride { get; init; }
}

/// <summary>
/// DTO for mobile check-in response
/// </summary>
public record MobileCheckInResultDto
{
    public bool Success { get; init; }
    public string? Message { get; init; }
    public DateTime? CheckInTime { get; init; }
    public string? GeofenceName { get; init; }
    public bool WasOutsideGeofence { get; init; }
    public double? DistanceFromGeofence { get; init; }
}

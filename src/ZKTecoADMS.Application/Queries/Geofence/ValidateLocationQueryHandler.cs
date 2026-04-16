using MediatR;
using ZKTecoADMS.Application.DTOs;
using ZKTecoADMS.Domain.Repositories;
using ZKTecoADMS.Application.Models;

namespace ZKTecoADMS.Application.Queries.Geofence;

public class ValidateLocationQueryHandler : IRequestHandler<ValidateLocationQuery, AppResponse<LocationValidationResultDto>>
{
    private readonly IRepository<Domain.Entities.Geofence> _geofenceRepository;

    public ValidateLocationQueryHandler(IRepository<Domain.Entities.Geofence> geofenceRepository)
    {
        _geofenceRepository = geofenceRepository;
    }

    public async Task<AppResponse<LocationValidationResultDto>> Handle(ValidateLocationQuery request, CancellationToken cancellationToken)
    {
        // Get active geofences for the store
        var geofences = await _geofenceRepository.GetAllWithIncludeAsync(
            g => g.StoreId == request.StoreId && g.IsActive,
            cancellationToken: cancellationToken);

        if (!geofences.Any())
        {
            return AppResponse<LocationValidationResultDto>.Success(new LocationValidationResultDto
            {
                IsWithinGeofence = true, // If no geofences configured, allow check-in
                Message = "Không có geofence nào được cấu hình"
            });
        }

        // Check each geofence, prioritizing primary
        foreach (var geofence in geofences.OrderByDescending(g => g.IsPrimary))
        {
            var distance = CalculateHaversineDistance(
                request.Latitude, request.Longitude,
                geofence.Latitude, geofence.Longitude);

            if (distance <= geofence.RadiusMeters)
            {
                return AppResponse<LocationValidationResultDto>.Success(new LocationValidationResultDto
                {
                    IsWithinGeofence = true,
                    MatchedGeofenceId = geofence.Id,
                    MatchedGeofenceName = geofence.Name,
                    DistanceFromCenter = Math.Round(distance, 2),
                    AllowedRadius = geofence.RadiusMeters,
                    CanCheckInOutside = geofence.AllowOutsideCheckIn,
                    Message = $"Bạn đang ở trong vùng {geofence.Name}"
                });
            }
        }

        // Not within any geofence - find the closest one
        var closest = geofences
            .Select(g => new
            {
                Geofence = g,
                Distance = CalculateHaversineDistance(
                    request.Latitude, request.Longitude,
                    g.Latitude, g.Longitude)
            })
            .OrderBy(x => x.Distance)
            .First();

        return AppResponse<LocationValidationResultDto>.Success(new LocationValidationResultDto
        {
            IsWithinGeofence = false,
            MatchedGeofenceId = closest.Geofence.Id,
            MatchedGeofenceName = closest.Geofence.Name,
            DistanceFromCenter = Math.Round(closest.Distance, 2),
            AllowedRadius = closest.Geofence.RadiusMeters,
            CanCheckInOutside = closest.Geofence.AllowOutsideCheckIn,
            Message = $"Bạn cách {closest.Geofence.Name} {Math.Round(closest.Distance - closest.Geofence.RadiusMeters, 0)}m"
        });
    }

    /// <summary>
    /// Calculate distance between two points using Haversine formula
    /// </summary>
    /// <returns>Distance in meters</returns>
    private static double CalculateHaversineDistance(double lat1, double lon1, double lat2, double lon2)
    {
        const double EarthRadiusMeters = 6371000;

        var dLat = DegreesToRadians(lat2 - lat1);
        var dLon = DegreesToRadians(lon2 - lon1);

        var a = Math.Sin(dLat / 2) * Math.Sin(dLat / 2) +
                Math.Cos(DegreesToRadians(lat1)) * Math.Cos(DegreesToRadians(lat2)) *
                Math.Sin(dLon / 2) * Math.Sin(dLon / 2);

        var c = 2 * Math.Atan2(Math.Sqrt(a), Math.Sqrt(1 - a));

        return EarthRadiusMeters * c;
    }

    private static double DegreesToRadians(double degrees)
    {
        return degrees * Math.PI / 180;
    }
}

using MediatR;
using ZKTecoADMS.Application.DTOs;
using ZKTecoADMS.Domain.Repositories;
using ZKTecoADMS.Application.Models;

namespace ZKTecoADMS.Application.Queries.Geofence;

public class GetGeofencesQueryHandler : IRequestHandler<GetGeofencesQuery, AppResponse<List<GeofenceDto>>>
{
    private readonly IRepository<Domain.Entities.Geofence> _geofenceRepository;

    public GetGeofencesQueryHandler(IRepository<Domain.Entities.Geofence> geofenceRepository)
    {
        _geofenceRepository = geofenceRepository;
    }

    public async Task<AppResponse<List<GeofenceDto>>> Handle(GetGeofencesQuery request, CancellationToken cancellationToken)
    {
        var geofences = await _geofenceRepository.GetAllWithIncludeAsync(
            g => g.StoreId == request.StoreId && 
                 (!request.ActiveOnly.HasValue || g.IsActive == request.ActiveOnly.Value),
            cancellationToken: cancellationToken);

        var result = geofences
            .OrderByDescending(g => g.IsPrimary)
            .ThenBy(g => g.Name)
            .Select(g => new GeofenceDto
            {
                Id = g.Id,
                StoreId = g.StoreId,
                Name = g.Name,
                Description = g.Description,
                Latitude = g.Latitude,
                Longitude = g.Longitude,
                RadiusMeters = g.RadiusMeters,
                Address = g.Address,
                IsActive = g.IsActive,
                IsPrimary = g.IsPrimary,
                CheckInToleranceMinutes = g.CheckInToleranceMinutes,
                CheckOutToleranceMinutes = g.CheckOutToleranceMinutes,
                AllowOutsideCheckIn = g.AllowOutsideCheckIn,
                CreatedAt = g.CreatedAt,
                UpdatedAt = g.UpdatedAt,
            })
            .ToList();

        return AppResponse<List<GeofenceDto>>.Success(result);
    }
}

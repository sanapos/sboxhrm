using MediatR;
using ZKTecoADMS.Application.DTOs;
using ZKTecoADMS.Domain.Repositories;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Application.Commands.Geofence;

public class CreateGeofenceCommandHandler : IRequestHandler<CreateGeofenceCommand, AppResponse<GeofenceDto>>
{
    private readonly IRepository<Domain.Entities.Geofence> _geofenceRepository;

    public CreateGeofenceCommandHandler(IRepository<Domain.Entities.Geofence> geofenceRepository)
    {
        _geofenceRepository = geofenceRepository;
    }

    public async Task<AppResponse<GeofenceDto>> Handle(CreateGeofenceCommand request, CancellationToken cancellationToken)
    {
        var dto = request.Dto;

        // Validate radius
        if (dto.RadiusMeters <= 0)
        {
            return AppResponse<GeofenceDto>.Fail("Bán kính geofence phải lớn hơn 0");
        }

        // Validate coordinates
        if (dto.Latitude < -90 || dto.Latitude > 90)
        {
            return AppResponse<GeofenceDto>.Fail("Vĩ độ không hợp lệ (phải từ -90 đến 90)");
        }

        if (dto.Longitude < -180 || dto.Longitude > 180)
        {
            return AppResponse<GeofenceDto>.Fail("Kinh độ không hợp lệ (phải từ -180 đến 180)");
        }

        // If this is set as primary, unset other primary geofences
        if (dto.IsPrimary)
        {
            var existingPrimary = await _geofenceRepository.GetAllWithIncludeAsync(
                g => g.StoreId == request.StoreId && g.IsPrimary,
                cancellationToken: cancellationToken);

            foreach (var existing in existingPrimary)
            {
                existing.IsPrimary = false;
                await _geofenceRepository.UpdateAsync(existing, cancellationToken);
            }
        }

        var geofence = new Domain.Entities.Geofence
        {
            StoreId = request.StoreId,
            Name = dto.Name,
            Description = dto.Description,
            Latitude = dto.Latitude,
            Longitude = dto.Longitude,
            RadiusMeters = dto.RadiusMeters,
            Address = dto.Address,
            IsActive = true,
            IsPrimary = dto.IsPrimary,
            CheckInToleranceMinutes = dto.CheckInToleranceMinutes,
            CheckOutToleranceMinutes = dto.CheckOutToleranceMinutes,
            AllowOutsideCheckIn = dto.AllowOutsideCheckIn,
        };

        await _geofenceRepository.AddAsync(geofence, cancellationToken);

        var result = new GeofenceDto
        {
            Id = geofence.Id,
            StoreId = geofence.StoreId,
            Name = geofence.Name,
            Description = geofence.Description,
            Latitude = geofence.Latitude,
            Longitude = geofence.Longitude,
            RadiusMeters = geofence.RadiusMeters,
            Address = geofence.Address,
            IsActive = geofence.IsActive,
            IsPrimary = geofence.IsPrimary,
            CheckInToleranceMinutes = geofence.CheckInToleranceMinutes,
            CheckOutToleranceMinutes = geofence.CheckOutToleranceMinutes,
            AllowOutsideCheckIn = geofence.AllowOutsideCheckIn,
            CreatedAt = geofence.CreatedAt,
        };

        return AppResponse<GeofenceDto>.Success(result);
    }
}

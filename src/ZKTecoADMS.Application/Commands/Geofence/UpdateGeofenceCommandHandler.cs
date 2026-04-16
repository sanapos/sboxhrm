using MediatR;
using ZKTecoADMS.Application.DTOs;
using ZKTecoADMS.Domain.Repositories;
using ZKTecoADMS.Application.Models;

namespace ZKTecoADMS.Application.Commands.Geofence;

public class UpdateGeofenceCommandHandler : IRequestHandler<UpdateGeofenceCommand, AppResponse<GeofenceDto>>
{
    private readonly IRepository<Domain.Entities.Geofence> _geofenceRepository;

    public UpdateGeofenceCommandHandler(IRepository<Domain.Entities.Geofence> geofenceRepository)
    {
        _geofenceRepository = geofenceRepository;
    }

    public async Task<AppResponse<GeofenceDto>> Handle(UpdateGeofenceCommand request, CancellationToken cancellationToken)
    {
        var geofence = await _geofenceRepository.GetByIdAsync(request.Id, cancellationToken: cancellationToken);
        if (geofence == null || geofence.StoreId != request.StoreId)
        {
            return AppResponse<GeofenceDto>.Fail("Geofence không tồn tại");
        }

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
        if (dto.IsPrimary && !geofence.IsPrimary)
        {
            var existingPrimary = await _geofenceRepository.GetAllWithIncludeAsync(
                g => g.StoreId == request.StoreId && g.IsPrimary && g.Id != request.Id,
                cancellationToken: cancellationToken);

            foreach (var existing in existingPrimary)
            {
                existing.IsPrimary = false;
                await _geofenceRepository.UpdateAsync(existing, cancellationToken);
            }
        }

        geofence.Name = dto.Name;
        geofence.Description = dto.Description;
        geofence.Latitude = dto.Latitude;
        geofence.Longitude = dto.Longitude;
        geofence.RadiusMeters = dto.RadiusMeters;
        geofence.Address = dto.Address;
        geofence.IsActive = dto.IsActive;
        geofence.IsPrimary = dto.IsPrimary;
        geofence.CheckInToleranceMinutes = dto.CheckInToleranceMinutes;
        geofence.CheckOutToleranceMinutes = dto.CheckOutToleranceMinutes;
        geofence.AllowOutsideCheckIn = dto.AllowOutsideCheckIn;

        await _geofenceRepository.UpdateAsync(geofence, cancellationToken);

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
            UpdatedAt = geofence.UpdatedAt,
        };

        return AppResponse<GeofenceDto>.Success(result);
    }
}

using MediatR;
using ZKTecoADMS.Domain.Repositories;
using ZKTecoADMS.Application.Models;

namespace ZKTecoADMS.Application.Commands.Geofence;

public class DeleteGeofenceCommandHandler : IRequestHandler<DeleteGeofenceCommand, AppResponse<bool>>
{
    private readonly IRepository<Domain.Entities.Geofence> _geofenceRepository;

    public DeleteGeofenceCommandHandler(IRepository<Domain.Entities.Geofence> geofenceRepository)
    {
        _geofenceRepository = geofenceRepository;
    }

    public async Task<AppResponse<bool>> Handle(DeleteGeofenceCommand request, CancellationToken cancellationToken)
    {
        var geofence = await _geofenceRepository.GetByIdAsync(request.Id, cancellationToken: cancellationToken);
        if (geofence == null || geofence.StoreId != request.StoreId)
        {
            return AppResponse<bool>.Fail("Geofence không tồn tại");
        }

        // Soft delete
        geofence.Deleted = DateTime.UtcNow;
        await _geofenceRepository.UpdateAsync(geofence, cancellationToken);

        return AppResponse<bool>.Success(true);
    }
}

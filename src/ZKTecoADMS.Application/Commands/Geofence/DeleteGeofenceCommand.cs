using MediatR;
using ZKTecoADMS.Application.Models;

namespace ZKTecoADMS.Application.Commands.Geofence;

public record DeleteGeofenceCommand(Guid Id, Guid StoreId) : IRequest<AppResponse<bool>>;

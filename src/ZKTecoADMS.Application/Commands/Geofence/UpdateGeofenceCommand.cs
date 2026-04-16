using MediatR;
using ZKTecoADMS.Application.DTOs;
using ZKTecoADMS.Application.Models;

namespace ZKTecoADMS.Application.Commands.Geofence;

public record UpdateGeofenceCommand(Guid Id, UpdateGeofenceDto Dto, Guid StoreId) : IRequest<AppResponse<GeofenceDto>>;

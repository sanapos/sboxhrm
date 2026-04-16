using MediatR;
using ZKTecoADMS.Application.DTOs;
using ZKTecoADMS.Application.Models;

namespace ZKTecoADMS.Application.Queries.Geofence;

public record GetGeofencesQuery(Guid StoreId, bool? ActiveOnly = null) : IRequest<AppResponse<List<GeofenceDto>>>;

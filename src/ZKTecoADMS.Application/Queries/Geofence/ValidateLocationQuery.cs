using MediatR;
using ZKTecoADMS.Application.DTOs;
using ZKTecoADMS.Application.Models;

namespace ZKTecoADMS.Application.Queries.Geofence;

public record ValidateLocationQuery(double Latitude, double Longitude, Guid StoreId) 
    : IRequest<AppResponse<LocationValidationResultDto>>;

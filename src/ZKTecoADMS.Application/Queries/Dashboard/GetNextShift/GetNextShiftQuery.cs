using ZKTecoADMS.Application.DTOs.Dashboard;
using ZKTecoADMS.Application.Models;

namespace ZKTecoADMS.Application.Queries.Dashboard.GetNextShift;

public record GetNextShiftQuery(Guid UserId) : IQuery<AppResponse<ShiftInfoDto>>;

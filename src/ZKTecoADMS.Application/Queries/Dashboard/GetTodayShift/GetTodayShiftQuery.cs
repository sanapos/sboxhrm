using ZKTecoADMS.Application.DTOs.Dashboard;
using ZKTecoADMS.Application.Models;

namespace ZKTecoADMS.Application.Queries.Dashboard.GetTodayShift;

public record GetTodayShiftQuery(Guid UserId) : IQuery<AppResponse<ShiftInfoDto>>;

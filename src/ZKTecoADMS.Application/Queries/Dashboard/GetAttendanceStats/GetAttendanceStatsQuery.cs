using ZKTecoADMS.Application.DTOs.Dashboard;
using ZKTecoADMS.Application.Models;

namespace ZKTecoADMS.Application.Queries.Dashboard.GetAttendanceStats;

public record GetAttendanceStatsQuery(
    Guid UserId,
    string Period = "month"
) : IQuery<AppResponse<AttendanceStatsDto>>;

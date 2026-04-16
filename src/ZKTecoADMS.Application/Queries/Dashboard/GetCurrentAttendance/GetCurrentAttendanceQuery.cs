using ZKTecoADMS.Application.DTOs.Dashboard;
using ZKTecoADMS.Application.Models;

namespace ZKTecoADMS.Application.Queries.Dashboard.GetCurrentAttendance;

public record GetCurrentAttendanceQuery(Guid UserId) : IQuery<AppResponse<AttendanceInfoDto>>;

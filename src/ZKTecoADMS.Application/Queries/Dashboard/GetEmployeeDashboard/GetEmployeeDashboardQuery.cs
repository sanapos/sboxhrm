using ZKTecoADMS.Application.DTOs.Dashboard;
using ZKTecoADMS.Application.Models;

namespace ZKTecoADMS.Application.Queries.Dashboard.GetEmployeeDashboard;

public record GetEmployeeDashboardQuery(
    Guid UserId,
    string Period = "month" // week, month, year
) : IQuery<AppResponse<EmployeeDashboardDto>>;

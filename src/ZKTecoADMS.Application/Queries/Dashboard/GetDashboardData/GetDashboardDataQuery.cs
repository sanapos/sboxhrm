using ZKTecoADMS.Application.DTOs.Dashboard;

namespace ZKTecoADMS.Application.Queries.Dashboard.GetDashboardData;

public record GetDashboardDataQuery(
    DateTime StartDate,
    DateTime EndDate,
    Guid EmployeeId,
    string? Department = null,
    int TopPerformersCount = 10,
    int LateEmployeesCount = 10,
    int TrendDays = 30
) : IQuery<AppResponse<DashboardDataDto>>;

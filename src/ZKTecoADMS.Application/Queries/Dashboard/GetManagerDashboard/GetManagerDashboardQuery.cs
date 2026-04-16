using ZKTecoADMS.Application.DTOs.Dashboard;
using ZKTecoADMS.Application.Models;

namespace ZKTecoADMS.Application.Queries.Dashboard.GetManagerDashboard;

public record GetManagerDashboardQuery(
    Guid ManagerUserId,
    DateTime Date,
    string UserRole = "",
    Guid? StoreId = null
) : IQuery<AppResponse<ManagerDashboardDto>>;

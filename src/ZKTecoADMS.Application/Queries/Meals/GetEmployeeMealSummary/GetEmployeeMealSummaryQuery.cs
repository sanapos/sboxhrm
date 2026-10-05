using ZKTecoADMS.Application.DTOs.Meals;

namespace ZKTecoADMS.Application.Queries.Meals.GetEmployeeMealSummary;

/// <summary>
/// Tổng hợp số xuất ăn theo từng nhân viên trong khoảng thời gian
/// </summary>
public record GetEmployeeMealSummaryQuery(
    Guid StoreId,
    DateTime FromDate,
    DateTime ToDate,
    Guid? EmployeeUserId,
    Guid? BranchId = null,
    /// <summary>Trụ sở: lọc trụ sở thì tính cả NV chưa gắn chi nhánh.</summary>
    Guid? HeadquarterId = null
) : IQuery<AppResponse<List<EmployeeMealSummaryDto>>>;

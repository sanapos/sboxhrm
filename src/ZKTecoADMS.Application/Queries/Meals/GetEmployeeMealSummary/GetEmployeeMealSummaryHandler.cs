using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.DTOs.Meals;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Application.Queries.Meals.GetEmployeeMealSummary;

public class GetEmployeeMealSummaryHandler(
    IRepository<MealRecord> mealRecordRepository,
    IRepository<Employee> employeeRepository
) : IQueryHandler<GetEmployeeMealSummaryQuery, AppResponse<List<EmployeeMealSummaryDto>>>
{
    public async Task<AppResponse<List<EmployeeMealSummaryDto>>> Handle(
        GetEmployeeMealSummaryQuery request, CancellationToken cancellationToken)
    {
        var from = request.FromDate.Date;
        var to = request.ToDate.Date;

        var records = await mealRecordRepository.GetAllWithIncludeAsync(
            filter: r => r.StoreId == request.StoreId &&
                         r.Date >= from && r.Date <= to &&
                         (!request.EmployeeUserId.HasValue || r.EmployeeUserId == request.EmployeeUserId.Value),
            includes: q => q.Include(r => r.EmployeeUser).Include(r => r.MealSession),
            cancellationToken: cancellationToken);

        var grouped = records
            .GroupBy(r => r.EmployeeUserId)
            .Select(g =>
            {
                var first = g.First();
                var employeeName = first.EmployeeUser != null
                    ? $"{first.EmployeeUser.LastName} {first.EmployeeUser.FirstName}".Trim()
                    : first.PIN ?? "";

                return new EmployeeMealSummaryDto
                {
                    EmployeeUserId = g.Key,
                    EmployeeName = employeeName,
                    TotalMeals = g.Count(),
                    Details = g.OrderBy(r => r.Date).ThenBy(r => r.MealTime).Select(r => new MealDetailDto
                    {
                        Date = r.Date,
                        MealSessionName = r.MealSession?.Name ?? "",
                        MealTime = r.MealTime
                    }).ToList()
                };
            })
            .OrderBy(e => e.EmployeeName)
            .ToList();

        // Enrich with employee code
        if (grouped.Count > 0)
        {
            var employeeUserIds = grouped.Select(g => g.EmployeeUserId).ToList();
            var employees = await employeeRepository.GetAllAsync(
                filter: e => e.ApplicationUserId.HasValue && employeeUserIds.Contains(e.ApplicationUserId.Value),
                cancellationToken: cancellationToken);

            foreach (var summary in grouped)
            {
                var emp = employees.FirstOrDefault(e => e.ApplicationUserId == summary.EmployeeUserId);
                if (emp != null)
                    summary.EmployeeCode = emp.EmployeeCode;
            }
        }

        return AppResponse<List<EmployeeMealSummaryDto>>.Success(grouped);
    }
}

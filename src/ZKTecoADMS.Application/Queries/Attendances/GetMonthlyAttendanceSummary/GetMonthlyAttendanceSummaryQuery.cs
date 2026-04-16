using ZKTecoADMS.Application.CQRS;
using ZKTecoADMS.Application.DTOs.Attendances;
using ZKTecoADMS.Application.Models;

namespace ZKTecoADMS.Application.Queries.Attendances.GetMonthlyAttendanceSummary;

public record GetMonthlyAttendanceSummaryQuery(
    List<Guid> EmployeeIds,
    int Year,
    int Month
) : IQuery<AppResponse<List<MonthlyAttendanceSummaryDto>>>;

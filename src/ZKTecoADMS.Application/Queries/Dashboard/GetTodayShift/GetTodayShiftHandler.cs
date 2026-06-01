using ZKTecoADMS.Application.DTOs.Dashboard;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Queries.Dashboard.GetTodayShift;

public class GetTodayShiftHandler(IRepository<Shift> shiftRepository)
    : IQueryHandler<GetTodayShiftQuery, AppResponse<ShiftInfoDto>>
{
    public async Task<AppResponse<ShiftInfoDto>> Handle(
        GetTodayShiftQuery request,
        CancellationToken cancellationToken)
    {
        // "Today" must always be VN-local date — server may run in UTC.
        var todayLocal = DateTime.UtcNow.AddHours(7).Date;
        var tomorrowLocal = todayLocal.AddDays(1);

        var todayShift = await shiftRepository.GetFirstOrDefaultAsync(
            s => s.StartTime,
            filter: s => s.EmployeeUserId == request.UserId
                && s.Status == ShiftStatus.Approved
                && s.StartTime >= todayLocal
                && s.StartTime < tomorrowLocal,
            cancellationToken: cancellationToken);

        if (todayShift == null)
        {
            return AppResponse<ShiftInfoDto>.Success(null);
        }

        var dto = new ShiftInfoDto
        {
            Id = todayShift.Id,
            StartTime = todayShift.StartTime,
            EndTime = todayShift.EndTime,
            Description = todayShift.Description,
            Status = (int)todayShift.Status,
        };

        return AppResponse<ShiftInfoDto>.Success(dto);
    }
}

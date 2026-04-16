using Microsoft.AspNetCore.Identity;
using ZKTecoADMS.Application.DTOs.Dashboard;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Queries.Dashboard.GetAttendanceStats;

public class GetAttendanceStatsHandler(
    IRepository<Shift> shiftRepository,
    IRepository<Attendance> attendanceRepository,
    UserManager<ApplicationUser> userRepository
) : IQueryHandler<GetAttendanceStatsQuery, AppResponse<AttendanceStatsDto>>
{
    public async Task<AppResponse<AttendanceStatsDto>> Handle(
        GetAttendanceStatsQuery request,
        CancellationToken cancellationToken)
    {
        var user = await userRepository.FindByIdAsync(request.UserId.ToString());
        if (user?.Employee == null)
        {
            return AppResponse<AttendanceStatsDto>.Success(new AttendanceStatsDto { Period = request.Period });
        }

        var (startDate, endDate) = GetDateRange(request.Period);
        
      
        return AppResponse<AttendanceStatsDto>.Success(null);
    }

    private static (DateTime startDate, DateTime endDate) GetDateRange(string period)
    {
        var now = DateTime.Now;
        var endDate = now.Date;

        return period.ToLower() switch
        {
            "week" => (now.AddDays(-7).Date, endDate),
            "year" => (now.AddYears(-1).Date, endDate),
            _ => (now.AddMonths(-1).Date, endDate)
        };
    }
}

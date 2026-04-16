using MediatR;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.DTOs.Dashboard;
using ZKTecoADMS.Application.Extensions;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Queries.Dashboard.GetEmployeeDashboard;

public class GetEmployeeDashboardHandler(
    IRepository<Shift> shiftRepository,
    IRepository<Attendance> attendanceRepository,
    UserManager<ApplicationUser> userManager,
    IShiftService shiftService
) : IQueryHandler<GetEmployeeDashboardQuery, AppResponse<EmployeeDashboardDto>>
{
    public async Task<AppResponse<EmployeeDashboardDto>> Handle(
        GetEmployeeDashboardQuery request,
        CancellationToken cancellationToken)
    {
        var user = await userManager.Users.Where(u => u.Id == request.UserId).Include(u => u.Employee).FirstOrDefaultAsync(cancellationToken);
        if (user == null)
        {
            return AppResponse<EmployeeDashboardDto>.Fail("User not found");
        }
        var (todayShift, nextShift) = await shiftService.GetTodayShiftAndNextShiftAsync(request.UserId, cancellationToken);

        var currentAttendance = new AttendanceInfoDto
        {
            CheckInTime = todayShift?.CheckInAttendance?.AttendanceTime ?? null,
            CheckOutTime = todayShift?.CheckOutAttendance?.AttendanceTime ?? null,
            Status = todayShift == null ? "no-shift" :
                     todayShift.CheckInAttendanceId == null ? "not-started" :
                     todayShift.CheckOutAttendanceId == null ? "checked-in" : "checked-out",
        };
        var dashboardData = new EmployeeDashboardDto
        {
            TodayShift = todayShift.Adapt<ShiftInfoDto>(),
            NextShift = nextShift.Adapt<ShiftInfoDto>(),
            CurrentAttendance = currentAttendance,
            AttendanceStats = await GetAttendanceStats(user, request.Period, cancellationToken)
        };

        return AppResponse<EmployeeDashboardDto>.Success(dashboardData);
    }

    private async Task<(ShiftInfoDto?, ShiftInfoDto?)> GetCurrentShiftAndNextShiftAsync(Guid userId, CancellationToken cancellationToken)
    {
        var today = DateTime.Now.Date;
        var todayShifts = await shiftRepository.GetAllAsync(
            s => s.EmployeeUserId == userId && 
                s.Status == ShiftStatus.Approved &&
                s.StartTime.Date == today,
            cancellationToken: cancellationToken
        );
        var currentShift = todayShifts.FirstOrDefault(
            s => s.StartTime <= DateTime.Now && 
            s.EndTime >= DateTime.Now);

        var nextShift = await shiftRepository.GetSingleAsync(
            s => s.EmployeeUserId == userId && 
            s.Status == ShiftStatus.Approved && 
            s.StartTime > DateTime.Now,
            cancellationToken: cancellationToken
        );
       
        var currentShiftDto = currentShift?.Adapt<ShiftInfoDto>();
        var nextShiftDto = nextShift?.Adapt<ShiftInfoDto>();

        return (currentShiftDto, nextShiftDto);
    }

    private async Task<AttendanceInfoDto?> GetCurrentAttendance(
        ApplicationUser user,
        ShiftInfoDto? todayShift,
        ShiftInfoDto? nextShift,
        CancellationToken cancellationToken)
    {
        if (user.Employee == null) return null;

        var today = DateTime.Now.Date;
        var todayAttendances = await attendanceRepository.GetAllAsync(
            a => a.EmployeeId == user.Employee.Id && a.AttendanceTime.Date == today,
            orderBy: q => q.OrderBy(a => a.AttendanceTime),
            cancellationToken: cancellationToken
        );
        
        if (!todayAttendances.Any()) return null;

        var checkIn = todayAttendances.FirstOrDefault();
        var checkOut = todayAttendances.LastOrDefault(a => a.AttendanceTime <= (nextShift == null || !nextShift.IsToday ? DateTime.Today.EndOfDay() : nextShift.StartTime));

        var checkInTime = checkIn?.AttendanceTime;
        var checkOutTime = checkOut?.AttendanceTime;

        // Determine status
        string status = "not-started";
        if (checkInTime.HasValue && !checkOutTime.HasValue)
            status = "checked-in";
        else if (checkInTime.HasValue && checkOutTime.HasValue)
            status = "checked-out";

        // Calculate work hours
        double workHours = 0;
        if (checkInTime.HasValue && checkOutTime.HasValue)
        {
            workHours = (checkOutTime.Value - checkInTime.Value).TotalHours;
        }
        else if (checkInTime.HasValue)
        {
            workHours = (DateTime.Now - checkInTime.Value).TotalHours;
        }

        // Check for late/early
        bool isLate = false;
        int? lateMinutes = null;
        bool isEarlyOut = false;
        int? earlyOutMinutes = null;

        // Get Current Shift to compare
        if (todayShift != null && checkInTime.HasValue)
        {
            var expectedStartTime = todayShift.StartTime;
            if (checkInTime.Value > expectedStartTime)
            {
                isLate = true;
                lateMinutes = (int)(checkInTime.Value - expectedStartTime).TotalMinutes;
            }

            if (checkOutTime.HasValue)
            {
                var expectedEndTime = todayShift.EndTime;
                if (checkOutTime.Value < expectedEndTime)
                {
                    isEarlyOut = true;
                    earlyOutMinutes = (int)(expectedEndTime - checkOutTime.Value).TotalMinutes;
                }
            }
        }

        return new AttendanceInfoDto
        {
            Id = checkIn?.Id ?? Guid.NewGuid(),
            CheckInTime = checkInTime,
            CheckOutTime = checkOutTime,
            Status = status,
            IsLate = isLate,
            IsEarlyOut = isEarlyOut,
            LateMinutes = lateMinutes,
            EarlyOutMinutes = earlyOutMinutes
        };
    }

    private async Task<AttendanceStatsDto> GetAttendanceStats(
        ApplicationUser user,
        string period,
        CancellationToken cancellationToken)
    {
        if (user.Employee == null)
        {
            return new AttendanceStatsDto { Period = period };
        }

        var (startDate, endDate) = GetDateRange(period);
        
        // Server-side filtered queries instead of loading entire tables
        var workShifts = (await shiftRepository.GetAllAsync(
            filter: s => s.EmployeeUserId == user.Id
                && s.Status == ShiftStatus.Approved
                && s.StartTime.Date >= startDate
                && s.StartTime.Date <= endDate,
            orderBy: q => q.OrderBy(s => s.StartTime),
            cancellationToken: cancellationToken
        )).ToList();

        var totalWorkDays = workShifts.Count;
        if (totalWorkDays == 0)
        {
            return new AttendanceStatsDto
            {
                Period = period,
                TotalWorkDays = 0
            };
        }

        int presentDays = 0;
        int lateCheckIns = 0;
        int earlyCheckOuts = 0;
        double totalWorkHours = 0;

        foreach (var shift in workShifts)
        {
            var shiftDate = shift.StartTime.Date;
            
        }

        int absentDays = totalWorkDays - presentDays;
        double attendanceRate = totalWorkDays > 0 ? (presentDays * 100.0 / totalWorkDays) : 0;
        double punctualityRate = presentDays > 0 ? ((presentDays - lateCheckIns) * 100.0 / presentDays) : 100;
        string avgWorkHours = presentDays > 0 ? (totalWorkHours / presentDays).ToString("F1") : "0.0";

        return new AttendanceStatsDto
        {
            TotalWorkDays = totalWorkDays,
            PresentDays = presentDays,
            AbsentDays = absentDays,
            LateCheckIns = lateCheckIns,
            EarlyCheckOuts = earlyCheckOuts,
            AttendanceRate = Math.Round(attendanceRate, 2),
            PunctualityRate = Math.Round(punctualityRate, 2),
            AverageWorkHours = avgWorkHours,
            Period = period
        };
    }

    private static (DateTime startDate, DateTime endDate) GetDateRange(string period)
    {
        var now = DateTime.Now;
        var endDate = now.Date;

        return period.ToLower() switch
        {
            "week" => (now.AddDays(-7).Date, endDate),
            "year" => (now.AddYears(-1).Date, endDate),
            _ => (now.AddMonths(-1).Date, endDate) // default to month
        };
    }
}

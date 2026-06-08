using MediatR;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.DTOs.Dashboard;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Queries.Dashboard.GetEmployeeDashboard;

/// <summary>
/// Trả dashboard cho 1 nhân viên: ca hôm nay, ca tiếp theo, trạng thái chấm
/// công hôm nay và thống kê chấm công cho period (week/month/year).
///
/// Quy ước thời gian (đồng nhất màn Chấm công thô):
///   • Attendance.AttendanceTime lưu giờ VN (timestamp without time zone).
///   • Lọc theo ngày lịch: AttendanceTime.Date (không quy đổi UTC).
///   • Shift.StartTime/EndTime lưu local VN — so sánh trực tiếp với AttendanceTime.
/// </summary>
public class GetEmployeeDashboardHandler(
    IRepository<Shift> shiftRepository,
    IRepository<Attendance> attendanceRepository,
    IRepository<DeviceUser> deviceUserRepository,
    UserManager<ApplicationUser> userManager,
    IShiftService shiftService
) : IQueryHandler<GetEmployeeDashboardQuery, AppResponse<EmployeeDashboardDto>>
{
    private const int VnOffsetHours = 7;

    public async Task<AppResponse<EmployeeDashboardDto>> Handle(
        GetEmployeeDashboardQuery request,
        CancellationToken cancellationToken)
    {
        var user = await userManager.Users
            .Where(u => u.Id == request.UserId)
            .Include(u => u.Employee)
            .FirstOrDefaultAsync(cancellationToken);
        if (user == null)
        {
            return AppResponse<EmployeeDashboardDto>.Fail("User not found");
        }

        var (todayShift, nextShift) = await shiftService
            .GetTodayShiftAndNextShiftAsync(request.UserId, cancellationToken);

        var currentAttendance = await BuildCurrentAttendance(user, todayShift, cancellationToken);
        var stats = await BuildAttendanceStats(user, request.Period, cancellationToken);

        var dashboardData = new EmployeeDashboardDto
        {
            TodayShift = todayShift.Adapt<ShiftInfoDto>(),
            NextShift = nextShift.Adapt<ShiftInfoDto>(),
            CurrentAttendance = currentAttendance,
            AttendanceStats = stats
        };

        return AppResponse<EmployeeDashboardDto>.Success(dashboardData);
    }

    // ─────────────────────────────────────────────────────────────────────
    // Current attendance — trạng thái chấm công của hôm nay (VN).
    // ─────────────────────────────────────────────────────────────────────

    private async Task<AttendanceInfoDto?> BuildCurrentAttendance(
        ApplicationUser user,
        Shift? todayShift,
        CancellationToken cancellationToken)
    {
        if (user.Employee == null) return null;

        var deviceUserIds = await AttendanceLogResolveHelper.GetDeviceUserIdsForHrEmployeeAsync(
            deviceUserRepository, user.Employee.Id, cancellationToken);
        if (deviceUserIds.Count == 0)
        {
            return new AttendanceInfoDto { Status = "not-started" };
        }

        var nowVn = DateTime.UtcNow.AddHours(VnOffsetHours);
        var todayLocal = nowVn.Date;
        var tomorrowLocal = todayLocal.AddDays(1);

        var todayPunches = await attendanceRepository.GetAllAsync(
            filter: a => a.EmployeeId != null
                && deviceUserIds.Contains(a.EmployeeId.Value)
                && a.AttendanceTime >= todayLocal
                && a.AttendanceTime < tomorrowLocal,
            orderBy: q => q.OrderBy(a => a.AttendanceTime),
            cancellationToken: cancellationToken);

        if (todayPunches.Count == 0)
        {
            return new AttendanceInfoDto { Status = "not-started" };
        }

        var checkIn = todayPunches.FirstOrDefault(a => a.AttendanceState == AttendanceStates.CheckIn)
            ?? todayPunches.First();
        var checkOut = todayPunches.LastOrDefault(a => a.AttendanceState == AttendanceStates.CheckOut);
        if (checkOut != null && checkOut.AttendanceTime <= checkIn.AttendanceTime)
            checkOut = null;

        var checkInLocal = checkIn.AttendanceTime;
        DateTime? checkOutLocal = checkOut?.AttendanceTime;

        bool isLate = false;
        int? lateMinutes = null;
        bool isEarlyOut = false;
        int? earlyOutMinutes = null;

        if (todayShift != null)
        {
            if (checkInLocal > todayShift.StartTime)
            {
                isLate = true;
                lateMinutes = (int)Math.Round((checkInLocal - todayShift.StartTime).TotalMinutes);
            }
            if (checkOutLocal.HasValue && checkOutLocal.Value < todayShift.EndTime)
            {
                isEarlyOut = true;
                earlyOutMinutes = (int)Math.Round((todayShift.EndTime - checkOutLocal.Value).TotalMinutes);
            }
        }

        var status = checkOutLocal.HasValue ? "checked-out" : "checked-in";
        var lastPunch = todayPunches[^1];

        return new AttendanceInfoDto
        {
            Id = checkIn.Id,
            CheckInTime = checkInLocal,
            CheckOutTime = checkOutLocal,
            LastPunchTime = lastPunch.AttendanceTime,
            LastPunchIsCheckOut = lastPunch.AttendanceState == AttendanceStates.CheckOut,
            Status = status,
            IsLate = isLate,
            IsEarlyOut = isEarlyOut,
            LateMinutes = lateMinutes,
            EarlyOutMinutes = earlyOutMinutes
        };
    }

    // ─────────────────────────────────────────────────────────────────────
    // Attendance stats — tổng hợp present/late/early/avg-hours cho period.
    // ─────────────────────────────────────────────────────────────────────

    private async Task<AttendanceStatsDto> BuildAttendanceStats(
        ApplicationUser user,
        string period,
        CancellationToken cancellationToken)
    {
        if (user.Employee == null)
        {
            return new AttendanceStatsDto { Period = period };
        }

        var deviceUserIds = await AttendanceLogResolveHelper.GetDeviceUserIdsForHrEmployeeAsync(
            deviceUserRepository, user.Employee.Id, cancellationToken);
        if (deviceUserIds.Count == 0)
        {
            return new AttendanceStatsDto { Period = period };
        }

        var (startLocal, endLocal) = GetDateRange(period);
        var rangeEndExclusive = endLocal.AddDays(1);

        // Approved shifts in the VN window (Shift.StartTime is already local).
        var shifts = await shiftRepository.GetAllAsync(
            filter: s => s.EmployeeUserId == user.Id
                && s.Status == ShiftStatus.Approved
                && s.StartTime >= startLocal
                && s.StartTime < endLocal.AddDays(1),
            orderBy: q => q.OrderBy(s => s.StartTime),
            cancellationToken: cancellationToken);

        var totalWorkDays = shifts.Count;
        if (totalWorkDays == 0)
        {
            return await BuildPunchBasedStatsAsync(
                deviceUserIds, startLocal, rangeEndExclusive, period, cancellationToken);
        }

        var attendances = await attendanceRepository.GetAllAsync(
            filter: a => a.EmployeeId != null
                && deviceUserIds.Contains(a.EmployeeId.Value)
                && a.AttendanceTime >= startLocal
                && a.AttendanceTime < rangeEndExclusive,
            orderBy: q => q.OrderBy(a => a.AttendanceTime),
            cancellationToken: cancellationToken);

        var attendanceByDate = attendances
            .GroupBy(a => a.AttendanceTime.Date)
            .ToDictionary(g => g.Key, g => g.OrderBy(a => a.AttendanceTime).ToList());

        var presentDays = 0;
        var lateCheckIns = 0;
        var earlyCheckOuts = 0;
        double totalWorkHours = 0;
        var workedFullDays = 0;

        foreach (var shift in shifts)
        {
            var shiftDate = shift.StartTime.Date;
            if (!attendanceByDate.TryGetValue(shiftDate, out var dayPunches) || dayPunches.Count == 0)
                continue;

            presentDays++;
            var firstIn = dayPunches.FirstOrDefault(a => a.AttendanceState == AttendanceStates.CheckIn)
                ?? dayPunches.First();
            var lastOut = dayPunches.LastOrDefault(a => a.AttendanceState == AttendanceStates.CheckOut)
                ?? dayPunches.Last();

            var inLocal = firstIn.AttendanceTime;
            var outLocal = lastOut.AttendanceTime;

            if (inLocal > shift.StartTime) lateCheckIns++;
            if (outLocal < shift.EndTime) earlyCheckOuts++;

            if (outLocal > inLocal)
            {
                totalWorkHours += (outLocal - inLocal).TotalHours;
                workedFullDays++;
            }
        }

        var absentDays = totalWorkDays - presentDays;
        var attendanceRate = totalWorkDays > 0
            ? Math.Round(presentDays * 100.0 / totalWorkDays, 2)
            : 0;
        var punctualityRate = presentDays > 0
            ? Math.Round((presentDays - lateCheckIns) * 100.0 / presentDays, 2)
            : 100;
        var avgWorkHours = workedFullDays > 0
            ? (totalWorkHours / workedFullDays).ToString("F1")
            : "0.0";

        return new AttendanceStatsDto
        {
            TotalWorkDays = totalWorkDays,
            PresentDays = presentDays,
            AbsentDays = absentDays,
            LateCheckIns = lateCheckIns,
            EarlyCheckOuts = earlyCheckOuts,
            AttendanceRate = attendanceRate,
            PunctualityRate = punctualityRate,
            AverageWorkHours = avgWorkHours,
            Period = period
        };
    }

    /// <summary>Fallback khi chưa có ca duyệt — thống kê theo ngày có log chấm công.</summary>
    private async Task<AttendanceStatsDto> BuildPunchBasedStatsAsync(
        List<Guid> deviceUserIds,
        DateTime rangeStart,
        DateTime rangeEndExclusive,
        string period,
        CancellationToken cancellationToken)
    {
        var attendances = await attendanceRepository.GetAllAsync(
            filter: a => a.EmployeeId != null
                && deviceUserIds.Contains(a.EmployeeId.Value)
                && a.AttendanceTime >= rangeStart
                && a.AttendanceTime < rangeEndExclusive,
            orderBy: q => q.OrderBy(a => a.AttendanceTime),
            cancellationToken: cancellationToken);

        var attendanceByDate = attendances
            .GroupBy(a => a.AttendanceTime.Date)
            .ToDictionary(g => g.Key, g => g.OrderBy(a => a.AttendanceTime).ToList());

        var presentDays = attendanceByDate.Count;
        if (presentDays == 0)
        {
            return new AttendanceStatsDto
            {
                Period = period,
                TotalWorkDays = 0,
                AttendanceRate = 0,
                PunctualityRate = 100,
                AverageWorkHours = "0.0"
            };
        }

        double totalWorkHours = 0;
        var workedFullDays = 0;

        foreach (var dayPunches in attendanceByDate.Values)
        {
            var firstIn = dayPunches.FirstOrDefault(a => a.AttendanceState == AttendanceStates.CheckIn)
                ?? dayPunches.First();
            var lastOut = dayPunches.LastOrDefault(a => a.AttendanceState == AttendanceStates.CheckOut)
                ?? dayPunches.Last();

            var inLocal = firstIn.AttendanceTime;
            var outLocal = lastOut.AttendanceTime;

            if (outLocal > inLocal)
            {
                totalWorkHours += (outLocal - inLocal).TotalHours;
                workedFullDays++;
            }
        }

        var avgWorkHours = workedFullDays > 0
            ? (totalWorkHours / workedFullDays).ToString("F1")
            : "0.0";

        return new AttendanceStatsDto
        {
            TotalWorkDays = presentDays,
            PresentDays = presentDays,
            AbsentDays = 0,
            LateCheckIns = 0,
            EarlyCheckOuts = 0,
            AttendanceRate = 100,
            PunctualityRate = 100,
            AverageWorkHours = avgWorkHours,
            Period = period
        };
    }

    private static (DateTime startLocal, DateTime endLocal) GetDateRange(string period)
    {
        var nowVn = DateTime.UtcNow.AddHours(VnOffsetHours);
        var endLocal = nowVn.Date;
        return period.ToLowerInvariant() switch
        {
            "week" => (nowVn.AddDays(-7).Date, endLocal),
            "year" => (nowVn.AddYears(-1).Date, endLocal),
            _ => (nowVn.AddMonths(-1).Date, endLocal),
        };
    }
}

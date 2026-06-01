using Microsoft.AspNetCore.Identity;
using ZKTecoADMS.Application.DTOs.Dashboard;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Queries.Dashboard.GetAttendanceStats;

/// <summary>
/// Thống kê chấm công của 1 nhân viên trong khoảng [week|month|year].
///
/// Quy ước thời gian (đồng nhất với ReportsController):
///   • <see cref="Attendance.AttendanceTime"/> được lưu dạng UTC
///     (EnableLegacyTimestampBehavior=true, Kind=Unspecified).
///   • So sánh ngày / khoảng ngày luôn quy về VN local (+7h) trước khi cắt theo .Date.
///   • Trễ/Sớm so với Shift.StartTime/EndTime — vì shift được lưu là local VN.
/// </summary>
public class GetAttendanceStatsHandler(
    IRepository<Shift> shiftRepository,
    IRepository<Attendance> attendanceRepository,
    UserManager<ApplicationUser> userManager
) : IQueryHandler<GetAttendanceStatsQuery, AppResponse<AttendanceStatsDto>>
{
    private const int VnOffsetHours = 7;

    public async Task<AppResponse<AttendanceStatsDto>> Handle(
        GetAttendanceStatsQuery request,
        CancellationToken cancellationToken)
    {
        var user = await userManager.FindByIdAsync(request.UserId.ToString());
        if (user?.Employee == null)
        {
            return AppResponse<AttendanceStatsDto>.Success(
                new AttendanceStatsDto { Period = request.Period });
        }

        var (startLocal, endLocal) = GetDateRange(request.Period);
        // Window in UTC for filtering AttendanceTime stored as UTC.
        var utcStart = startLocal.AddHours(-VnOffsetHours);
        var utcEnd = endLocal.AddDays(1).AddHours(-VnOffsetHours);

        // Approved shifts whose start (VN local) falls in [startLocal, endLocal].
        var shifts = await shiftRepository.GetAllAsync(
            filter: s => s.EmployeeUserId == request.UserId
                && s.Status == ShiftStatus.Approved
                && s.StartTime >= startLocal
                && s.StartTime < endLocal.AddDays(1),
            orderBy: q => q.OrderBy(s => s.StartTime),
            cancellationToken: cancellationToken);

        var totalWorkDays = shifts.Count;
        if (totalWorkDays == 0)
        {
            return AppResponse<AttendanceStatsDto>.Success(new AttendanceStatsDto
            {
                Period = request.Period,
                TotalWorkDays = 0,
                AttendanceRate = 0,
                PunctualityRate = 100,
                AverageWorkHours = "0.0"
            });
        }

        var employeeId = user.Employee.Id;
        var attendances = await attendanceRepository.GetAllAsync(
            filter: a => a.EmployeeId == employeeId
                && a.AttendanceTime >= utcStart
                && a.AttendanceTime < utcEnd,
            orderBy: q => q.OrderBy(a => a.AttendanceTime),
            cancellationToken: cancellationToken);

        // Group punches by VN-local date.
        var attendanceByDate = attendances
            .GroupBy(a => a.AttendanceTime.AddHours(VnOffsetHours).Date)
            .ToDictionary(g => g.Key, g => g.OrderBy(a => a.AttendanceTime).ToList());

        var presentDays = 0;
        var lateCheckIns = 0;
        var earlyCheckOuts = 0;
        double totalWorkHours = 0;
        var workedDays = 0;

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

            var inVn = firstIn.AttendanceTime.AddHours(VnOffsetHours);
            var outVn = lastOut.AttendanceTime.AddHours(VnOffsetHours);

            if (inVn > shift.StartTime) lateCheckIns++;
            if (outVn < shift.EndTime) earlyCheckOuts++;

            if (outVn > inVn)
            {
                totalWorkHours += (outVn - inVn).TotalHours;
                workedDays++;
            }
        }

        var absentDays = totalWorkDays - presentDays;
        var attendanceRate = totalWorkDays > 0
            ? Math.Round(presentDays * 100.0 / totalWorkDays, 2)
            : 0;
        // Punctuality = on-time days / present days. If no presence, treat as 100% (nothing to be late on).
        var punctualityRate = presentDays > 0
            ? Math.Round((presentDays - lateCheckIns) * 100.0 / presentDays, 2)
            : 100;
        var avgWorkHours = workedDays > 0
            ? (totalWorkHours / workedDays).ToString("F1")
            : "0.0";

        return AppResponse<AttendanceStatsDto>.Success(new AttendanceStatsDto
        {
            TotalWorkDays = totalWorkDays,
            PresentDays = presentDays,
            AbsentDays = absentDays,
            LateCheckIns = lateCheckIns,
            EarlyCheckOuts = earlyCheckOuts,
            AttendanceRate = attendanceRate,
            PunctualityRate = punctualityRate,
            AverageWorkHours = avgWorkHours,
            Period = request.Period
        });
    }

    private static (DateTime startLocal, DateTime endLocal) GetDateRange(string period)
    {
        // VN local "today" — robust regardless of server clock (Linux container = UTC).
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

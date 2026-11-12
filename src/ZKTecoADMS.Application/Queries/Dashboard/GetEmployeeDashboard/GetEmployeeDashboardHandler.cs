using MediatR;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.DTOs.Dashboard;
using AttendanceLogDto = ZKTecoADMS.Application.DTOs.Attendances.AttendanceDto;
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
    IRepository<Device> deviceRepository,
    IRepository<MobileAttendanceRecord> mobileAttendanceRepository,
    UserManager<ApplicationUser> userManager,
    IShiftService shiftService,
    IRepository<EmployeeBenefit> employeeBenefitRepository,
    IRepository<ShiftTemplate> shiftTemplateRepository,
    IRepository<ShiftSalaryLevel> shiftSalaryLevelRepository,
    IRepository<WorkSchedule> workScheduleRepository
) : IQueryHandler<GetEmployeeDashboardQuery, AppResponse<EmployeeDashboardDto>>
{
    private const int VnOffsetHours = 7;

    /// <summary>Biên lấy lượt chấm quanh khung ca (vào sớm / ra muộn tối đa).</summary>
    private const int PunchWindowHours = 4;

    private static readonly string[] ActiveMobileStatuses =
        ["pending", "approved", "auto_approved"];

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

        // Đi muộn / về sớm theo ca trong thiết lập lương (như bảng công, phiếu phạt, Tổng quan) — trước đây so với
        // ca đăng ký theo giờ (bảng Shift), không ân hạn: cửa hàng chỉ gán ca ở thiết lập lương thì không bao giờ báo trễ.
        var (salaryShifts, offToday) = await LoadSalaryShiftsAsync(user.Employee, cancellationToken);
        var currentAttendance = await BuildCurrentAttendance(user, todayShift, salaryShifts, cancellationToken);
        var stats = await BuildAttendanceStats(user, request.Period, salaryShifts, cancellationToken);
        var recentPunches = await BuildRecentPunches(user, request.Period, cancellationToken);

        // Không có ca đăng ký theo giờ: hiện ca trong thiết lập lương (trước Trang chủ ghi «Hôm nay không có ca»
        // với mọi cửa hàng chỉ gán ca ở thiết lập lương). Ngày nghỉ tuần của mẫu lương thì không có ca.
        var todayShiftDto = todayShift.Adapt<ShiftInfoDto>();

        // Ca xếp trên lịch hôm nay (Ca làm việc → bảng xếp ca): có thể nhiều ca. Ca hiện tại / sắp tới làm «ca hôm nay».
        var (todayShifts, scheduledOff) = await LoadScheduledTodayAsync(user.Employee, cancellationToken);
        if (todayShift == null && todayShifts.Count > 0)
        {
            var nowVn = DateTime.UtcNow.AddHours(VnOffsetHours);
            todayShiftDto = todayShifts.FirstOrDefault(s => s.StartTime <= nowVn && nowVn < s.EndTime)
                ?? todayShifts.FirstOrDefault(s => s.StartTime > nowVn)
                ?? todayShifts[^1];
        }
        if (scheduledOff) offToday = true;

        if (todayShiftDto == null && salaryShifts.Count > 0 && !offToday)
        {
            var today = DateTime.UtcNow.AddHours(VnOffsetHours).Date;
            var pick = currentAttendance?.CheckInTime is DateTime ci
                ? ShiftMatchHelper.FindBestForCheckIn(salaryShifts, ci.TimeOfDay)?.Shift
                : null;
            pick ??= salaryShifts.OrderBy(c => c.StartTime).First();
            var start = today + pick.StartTime;
            var end = today + pick.EndTime;
            if (end <= start) end = end.AddDays(1);
            todayShiftDto = new ShiftInfoDto { Id = pick.Id, StartTime = start, EndTime = end, Description = pick.Name, Status = 1 };
        }

        var dashboardData = new EmployeeDashboardDto
        {
            TodayShift = todayShiftDto,
            TodayShifts = todayShifts,
            NextShift = nextShift.Adapt<ShiftInfoDto>(),
            CurrentAttendance = currentAttendance,
            AttendanceStats = stats,
            RecentPunches = recentPunches
        };

        return AppResponse<EmployeeDashboardDto>.Success(dashboardData);
    }

    /// <summary>
    /// Ca xếp cho hôm nay trên lịch làm việc (mọi ca, theo giờ vào) và có phải ngày nghỉ trên lịch không.
    /// </summary>
    private async Task<(List<ShiftInfoDto> Shifts, bool DayOff)> LoadScheduledTodayAsync(Employee? employee, CancellationToken ct)
    {
        if (employee == null) return ([], false);
        var today = DateTime.UtcNow.AddHours(VnOffsetHours).Date;
        var tomorrow = today.AddDays(1);
        var rows = await workScheduleRepository.GetAllAsync(
            w => w.EmployeeUserId == employee.Id && w.Date >= today && w.Date < tomorrow
                 && (employee.StoreId == null || w.StoreId == employee.StoreId),
            includeProperties: [nameof(WorkSchedule.Shift)],
            cancellationToken: ct);
        var list = new List<ShiftInfoDto>();
        foreach (var w in rows.Where(w => !w.IsDayOff))
        {
            var startTs = w.StartTime ?? w.Shift?.StartTime;
            var endTs = w.EndTime ?? w.Shift?.EndTime;
            if (startTs == null || endTs == null) continue;
            var start = today + startTs.Value;
            var end = today + endTs.Value;
            if (end <= start) end = end.AddDays(1);
            list.Add(new ShiftInfoDto
            {
                Id = w.ShiftId ?? w.Id, StartTime = start, EndTime = end,
                Description = w.Shift?.Name ?? "Ca làm việc", Status = 1,
            });
        }
        list.Sort((a, b) => a.StartTime.CompareTo(b.StartTime));
        return (list, list.Count == 0 && rows.Any(w => w.IsDayOff));
    }

    // ─────────────────────────────────────────────────────────────────────
    // Current attendance — trạng thái chấm công của hôm nay (VN).
    // ─────────────────────────────────────────────────────────────────────

    private async Task<AttendanceInfoDto?> BuildCurrentAttendance(
        ApplicationUser user,
        Shift? todayShift,
        IReadOnlyList<ShiftMatchHelper.Candidate> salaryShifts,
        CancellationToken cancellationToken)
    {
        if (user.Employee == null) return null;

        var deviceUserIds = await AttendanceLogResolveHelper.GetDeviceUserIdsForHrEmployeeAsync(
            deviceUserRepository, user.Employee.Id, cancellationToken);

        var nowVn = DateTime.UtcNow.AddHours(VnOffsetHours);
        var todayLocal = nowVn.Date;
        var tomorrowLocal = todayLocal.AddDays(1);

        List<Attendance> todayPunches;
        if (deviceUserIds.Count == 0)
        {
            todayPunches = [];
        }
        else
        {
            todayPunches = await attendanceRepository.GetAllAsync(
                filter: a => a.EmployeeId != null
                    && deviceUserIds.Contains(a.EmployeeId.Value)
                    && a.AttendanceTime >= todayLocal
                    && a.AttendanceTime < tomorrowLocal,
                orderBy: q => q.OrderBy(a => a.AttendanceTime),
                cancellationToken: cancellationToken);
        }

        if (todayPunches.Count == 0)
        {
            var mobileToday = await GetTodayMobilePunchesAsync(
                user, todayLocal, tomorrowLocal, cancellationToken);
            if (mobileToday.Count == 0)
            {
                return new AttendanceInfoDto { Status = "not-started" };
            }

            return BuildCurrentAttendanceFromMobile(mobileToday, salaryShifts);
        }

        var checkIn = todayPunches.FirstOrDefault(a => a.AttendanceState == AttendanceStates.CheckIn)
            ?? todayPunches.First();
        var checkOut = todayPunches.LastOrDefault(a => a.AttendanceState == AttendanceStates.CheckOut);
        if (checkOut != null && checkOut.AttendanceTime <= checkIn.AttendanceTime)
            checkOut = null;

        var checkInLocal = checkIn.AttendanceTime;
        DateTime? checkOutLocal = checkOut?.AttendanceTime;

        var (lateMin, earlyMin) = LateEarly(salaryShifts, checkInLocal, checkOutLocal);
        var isLate = lateMin > 0;
        int? lateMinutes = isLate ? lateMin : null;
        var isEarlyOut = earlyMin > 0;
        int? earlyOutMinutes = isEarlyOut ? earlyMin : null;

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
        IReadOnlyList<ShiftMatchHelper.Candidate> salaryShifts,
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
                deviceUserIds, startLocal, rangeEndExclusive, period, salaryShifts, cancellationToken);
        }

        // Lấy dư 1 ngày cuối kỳ: ca đêm ngày cuối (22:00→06:00) có giờ ra sang sáng hôm sau.
        var attendances = (await attendanceRepository.GetAllAsync(
            filter: a => a.EmployeeId != null
                && deviceUserIds.Contains(a.EmployeeId.Value)
                && a.AttendanceTime >= startLocal.AddHours(-PunchWindowHours)
                && a.AttendanceTime < rangeEndExclusive.AddDays(1),
            orderBy: q => q.OrderBy(a => a.AttendanceTime),
            cancellationToken: cancellationToken)).ToList();

        var presentDays = 0;
        var lateCheckIns = 0;
        var earlyCheckOuts = 0;
        double totalWorkHours = 0;
        var workedFullDays = 0;

        foreach (var shift in shifts)
        {
            // Lượt chấm thuộc ca = trong khung [vào ca − 4h, ra ca + 4h] (Shift.Start/End là ngày-giờ đầy đủ)
            // → ca qua đêm có giờ vào hôm trước, giờ ra sáng hôm sau vẫn ghép đúng một ca
            //   (trước đây gom theo ngày lịch của giờ vào → mất giờ ra, tính về sớm / 0 giờ làm).
            var winFrom = shift.StartTime.AddHours(-PunchWindowHours);
            var winTo = shift.EndTime.AddHours(PunchWindowHours);
            var dayPunches = attendances
                .Where(a => a.AttendanceTime >= winFrom && a.AttendanceTime <= winTo)
                .OrderBy(a => a.AttendanceTime)
                .ToList();
            if (dayPunches.Count == 0)
                continue;

            presentDays++;
            var firstIn = dayPunches.FirstOrDefault(a => a.AttendanceState == AttendanceStates.CheckIn)
                ?? dayPunches.First();
            var lastOut = dayPunches.LastOrDefault(a => a.AttendanceState == AttendanceStates.CheckOut)
                ?? dayPunches.Last();

            var inLocal = firstIn.AttendanceTime;
            var outLocal = lastOut.AttendanceTime;

            var (lateMin, earlyMin) = LateEarly(salaryShifts, inLocal, outLocal > inLocal ? outLocal : null);
            if (lateMin > 0) lateCheckIns++;
            if (earlyMin > 0) earlyCheckOuts++;

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
        IReadOnlyList<ShiftMatchHelper.Candidate> salaryShifts,
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
        var lateCheckIns = 0;
        var earlyCheckOuts = 0;

        foreach (var dayPunches in attendanceByDate.Values)
        {
            var firstIn = dayPunches.FirstOrDefault(a => a.AttendanceState == AttendanceStates.CheckIn)
                ?? dayPunches.First();
            var lastOut = dayPunches.LastOrDefault(a => a.AttendanceState == AttendanceStates.CheckOut)
                ?? dayPunches.Last();

            var inLocal = firstIn.AttendanceTime;
            var outLocal = lastOut.AttendanceTime;
            var (lateMin, earlyMin) = LateEarly(salaryShifts, inLocal, outLocal > inLocal ? outLocal : null);
            if (lateMin > 0) lateCheckIns++;
            if (earlyMin > 0) earlyCheckOuts++;

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
            LateCheckIns = lateCheckIns,
            EarlyCheckOuts = earlyCheckOuts,
            AttendanceRate = 100,
            PunctualityRate = Math.Round((presentDays - lateCheckIns) * 100.0 / presentDays, 2),
            AverageWorkHours = avgWorkHours,
            Period = period
        };
    }

    private async Task<List<AttendanceLogDto>> BuildRecentPunches(
        ApplicationUser user,
        string period,
        CancellationToken cancellationToken)
    {
        if (user.Employee == null) return [];

        var deviceUserIds = await AttendanceLogResolveHelper.GetDeviceUserIdsForHrEmployeeAsync(
            deviceUserRepository, user.Employee.Id, cancellationToken);
        if (deviceUserIds.Count == 0) return [];

        var (startLocal, endLocal) = GetDateRange(period);
        var rangeEndExclusive = endLocal.AddDays(1);

        var punches = await attendanceRepository.GetAllAsync(
            filter: a => a.EmployeeId != null
                && deviceUserIds.Contains(a.EmployeeId.Value)
                && a.AttendanceTime >= startLocal
                && a.AttendanceTime < rangeEndExclusive,
            orderBy: q => q.OrderByDescending(a => a.AttendanceTime),
            take: 50,
            cancellationToken: cancellationToken);

        if (punches.Count == 0) return [];

        var deviceIds = punches.Select(p => p.DeviceId).Distinct().ToList();
        var devices = await deviceRepository.GetAllAsync(
            d => deviceIds.Contains(d.Id),
            cancellationToken: cancellationToken);
        var deviceNames = devices.ToDictionary(d => d.Id, d => d.DeviceName);

        var emp = user.Employee;
        var fullName = $"{emp.LastName} {emp.FirstName}".Trim();

        return punches.Select(a => new AttendanceLogDto(
            a.Id,
            a.AttendanceTime,
            deviceNames.GetValueOrDefault(a.DeviceId, "—"),
            a.PIN,
            emp.EmployeeCode,
            fullName,
            null,
            0,
            a.VerifyMode,
            a.AttendanceState,
            a.WorkCode,
            a.Note,
            a.MobileAttendanceRecordId,
            null,
            null,
            null,
            null
        )).ToList();
    }

    private async Task<List<MobileAttendanceRecord>> GetTodayMobilePunchesAsync(
        ApplicationUser user,
        DateTime todayLocal,
        DateTime tomorrowLocal,
        CancellationToken cancellationToken)
    {
        if (user.Employee == null) return [];

        var keys = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            user.Id.ToString(),
            user.Employee.Id.ToString(),
        };
        if (!string.IsNullOrWhiteSpace(user.Employee.EmployeeCode))
        {
            keys.Add(user.Employee.EmployeeCode.Trim());
        }

        return await mobileAttendanceRepository.GetAllAsync(
            filter: r => keys.Contains(r.OdooEmployeeId)
                && r.PunchTime >= todayLocal
                && r.PunchTime < tomorrowLocal
                && ActiveMobileStatuses.Contains(r.Status),
            orderBy: q => q.OrderBy(r => r.PunchTime),
            cancellationToken: cancellationToken);
    }

    /// <summary>Ca gán trong thiết lập lương: «shifts:» của mẫu lương đang áp dụng + mức lương ca (EmployeeIds).</summary>
    private async Task<(List<ShiftMatchHelper.Candidate> Shifts, bool OffToday)> LoadSalaryShiftsAsync(
        Employee? employee, CancellationToken ct)
    {
        if (employee == null) return ([], false);
        var today = DateTime.UtcNow.AddHours(VnOffsetHours).Date;
        var templates = await shiftTemplateRepository.GetAllAsync(
            filter: t => t.StoreId == employee.StoreId && t.IsActive, cancellationToken: ct);
        if (templates.Count == 0) return ([], false);

        static string Norm(string? x) =>
            System.Text.RegularExpressions.Regex.Replace((x ?? string.Empty).Trim().ToLowerInvariant(), @"\s+", " ");
        var chosen = new List<ShiftTemplate>();
        var benefit = (await employeeBenefitRepository.GetAllAsync(
                filter: eb => eb.EmployeeId == employee.Id && eb.EffectiveDate <= today.AddDays(1),
                includeProperties: [nameof(EmployeeBenefit.Benefit)], cancellationToken: ct))
            .OrderByDescending(eb => eb.EffectiveDate).FirstOrDefault()?.Benefit;
        foreach (var part in (benefit?.Description ?? string.Empty).Split('|'))
        {
            var i = part.IndexOf(':');
            if (i <= 0 || part[..i].Trim() != "shifts") continue;
            foreach (var name in part[(i + 1)..].Split(',', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries))
                if (templates.FirstOrDefault(t => Norm(t.Name) == Norm(name)) is { } st && !chosen.Contains(st))
                    chosen.Add(st);
        }
        var templateIds = templates.Select(t => t.Id).ToList();
        var key = employee.Id.ToString();
        var levels = await shiftSalaryLevelRepository.GetAllAsync(
            filter: l => templateIds.Contains(l.ShiftTemplateId) && l.EmployeeIds != null && l.EmployeeIds.Contains(key),
            cancellationToken: ct);
        foreach (var l in levels)
            if (templates.FirstOrDefault(t => t.Id == l.ShiftTemplateId) is { } st && !chosen.Contains(st))
                chosen.Add(st);

        var offToday = (benefit?.WeeklyOffDays ?? string.Empty)
            .Split(',', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries)
            .Any(d => string.Equals(d, today.DayOfWeek.ToString(), StringComparison.OrdinalIgnoreCase));
        return (chosen
            .Where(t => !(t.ShiftType ?? string.Empty).ToLowerInvariant().Contains("tăng ca"))
            .Select(t => new ShiftMatchHelper.Candidate(
                t.Id, t.StartTime, t.EndTime, t.LateGraceMinutes, t.EarlyLeaveGraceMinutes,
                t.MaximumAllowedLateMinutes > 0 ? t.MaximumAllowedLateMinutes : 30,
                t.EarlyCheckInMinutes > 0 ? t.EarlyCheckInMinutes : 30,
                t.MaximumAllowedEarlyLeaveMinutes > 0 ? t.MaximumAllowedEarlyLeaveMinutes : 120,
                t.ShiftType, t.Name))
            .ToList(), offToday);
    }

    /// <summary>Phút đi muộn (lượt vào) / về sớm (lượt ra) theo ca thiết lập lương khớp nhất; quá ân hạn thì đủ phút.</summary>
    private static (int Late, int Early) LateEarly(
        IReadOnlyList<ShiftMatchHelper.Candidate> salaryShifts, DateTime checkIn, DateTime? checkOut)
    {
        if (salaryShifts.Count == 0) return (0, 0);
        var inFit = ShiftMatchHelper.FindBestForCheckIn(salaryShifts, checkIn.TimeOfDay);
        var early = 0;
        if (checkOut.HasValue && inFit != null)
        {
            var outFit = ShiftMatchHelper.FindBest([inFit.Shift], checkIn.TimeOfDay, checkOut.Value.TimeOfDay);
            early = outFit?.EffectiveEarlyOut ?? 0;
        }
        return (inFit?.EffectiveLateIn ?? 0, early);
    }

    private static AttendanceInfoDto BuildCurrentAttendanceFromMobile(
        List<MobileAttendanceRecord> punches,
        IReadOnlyList<ShiftMatchHelper.Candidate> salaryShifts)
    {
        var checkInRec = punches.FirstOrDefault(p => p.PunchType == 0) ?? punches.First();
        var checkOutRec = punches.LastOrDefault(p => p.PunchType == 1);
        if (checkOutRec != null && checkOutRec.PunchTime <= checkInRec.PunchTime)
        {
            checkOutRec = null;
        }

        var checkInLocal = checkInRec.PunchTime;
        DateTime? checkOutLocal = checkOutRec?.PunchTime;

        var (lateMin, earlyMin) = LateEarly(salaryShifts, checkInLocal, checkOutLocal);
        var isLate = lateMin > 0;
        int? lateMinutes = isLate ? lateMin : null;
        var isEarlyOut = earlyMin > 0;
        int? earlyOutMinutes = isEarlyOut ? earlyMin : null;

        var lastPunch = punches[^1];
        var status = checkOutLocal.HasValue ? "checked-out" : "checked-in";

        return new AttendanceInfoDto
        {
            Id = checkInRec.Id,
            CheckInTime = checkInLocal,
            CheckOutTime = checkOutLocal,
            LastPunchTime = lastPunch.PunchTime,
            LastPunchIsCheckOut = lastPunch.PunchType == 1,
            Status = status,
            IsLate = isLate,
            IsEarlyOut = isEarlyOut,
            LateMinutes = lateMinutes,
            EarlyOutMinutes = earlyOutMinutes
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

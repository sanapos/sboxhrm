using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using System.Text;
using ClosedXML.Excel;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Helpers;
using ZKTecoADMS.Infrastructure.Services;

namespace ZKTecoADMS.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
public class ReportsController(
    ZKTecoDbContext dbContext,
    ILogger<ReportsController> logger
) : AuthenticatedControllerBase
{
    // Typed projection for ShiftTemplate used by daily report — using a named record
    // (vs anonymous types boxed into dynamic) avoids runtime cast issues when the
    // list is iterated in a different assembly/internal scope.
    private sealed record ShiftInfo(
        Guid Id,
        string Name,
        TimeSpan StartTime,
        TimeSpan EndTime,
        int LateGraceMinutes,
        int EarlyLeaveGraceMinutes);

    /// <summary>
    /// Build a VN (UTC+7) day range for querying UTC-stored timestamps.
    /// Returns (targetLocal, utcStart, utcEnd) where utcStart..utcEnd represents
    /// the VN working day [dayEnd, next-dayEnd). When <paramref name="date"/> is null, uses today (VN).
    /// dayEnd comes from AppSettings day_end_time (sole source of truth).
    /// </summary>
    private static (DateTime targetLocal, DateTime utcStart, DateTime utcEnd) VnDayRange(DateTime? date, TimeSpan? dayEndTime = null)
    {
        var targetLocal = (date ?? DateTime.UtcNow.AddHours(7)).Date;
        // Working day X = [X + day_end_time, X+1 + day_end_time).
        var cutoff = dayEndTime ?? TimeSpan.Zero;
        var utcStart = targetLocal.Add(cutoff).AddHours(-7);
        var utcEnd = utcStart.AddDays(1);
        return (targetLocal, utcStart, utcEnd);
    }

    private async Task<IQueryable<Employee>> FilterEmployeesQueryAsync(
        IQueryable<Employee> query,
        Guid storeId,
        string? department,
        Guid? branchId,
        bool includeChildBranches,
        string? employeeCodes,
        string? employeeCode = null)
    {
        if (!string.IsNullOrEmpty(department))
            query = query.Where(e => e.Department == department);

        if (!string.IsNullOrEmpty(employeeCode))
            query = query.Where(e => e.EmployeeCode.Contains(employeeCode));

        query = await BranchQueryHelper.ApplyBranchFilterAsync(
            query, dbContext, storeId, branchId, includeChildBranches);

        var codeFilter = ReportsExportHelpers.ParseEmployeeCodes(employeeCodes);
        if (codeFilter is { Count: > 0 })
            query = query.Where(e => codeFilter.Contains(e.EmployeeCode));

        return query;
    }

    #region Daily Attendance Report

    /// <summary>
    /// Get daily attendance report
    /// </summary>
    [HttpGet("attendance/daily")]
    [RequireAnyModulePermission(ModulePermissionAction.View, "AttendanceReport", "AttendanceSummary", "AttendanceByShift", "Attendance")]
    public async Task<ActionResult<AppResponse<DailyAttendanceReportDto>>> GetDailyAttendanceReport(
        [FromQuery] DateTime? date = null,
        [FromQuery] string? department = null,
        [FromQuery] string? employeeCode = null,
        [FromQuery] string? employeeCodes = null,
        [FromQuery] Guid? branchId = null,
        [FromQuery] bool includeChildBranches = true)
    {
        try
        {
            var storeId = RequiredStoreId;
            // Sole source: AppSettings day_end_time (ignore legacy overnightCutoff query)
            var cutoff = await AppSettingsOperationalHelper.ResolveDayEndTimeAsync(
                dbContext, storeId);
            var (targetDate, vnStart, vnEnd) = VnDayRange(date, cutoff);

            var employeesQuery = dbContext.Employees
                .Where(e => e.StoreId == storeId && e.Deleted == null);

            employeesQuery = await FilterEmployeesQueryAsync(
                employeesQuery, storeId, department, branchId, includeChildBranches, employeeCodes, employeeCode);

            var employees = await employeesQuery.ToListAsync();

            var employeeIds = employees.Select(e => e.Id).ToList();

            // Get DeviceUsers linked to these employees to map PIN -> Employee
            var deviceUsers = await dbContext.DeviceUsers
                .Where(du => du.EmployeeId.HasValue && employeeIds.Contains(du.EmployeeId.Value))
                .ToListAsync();

            // Build pin set: DeviceUser.Pin + Employee.EmployeeCode for backward compat
            var pinToEmployeeId = new Dictionary<string, Guid>();
            foreach (var du in deviceUsers)
            {
                if (du.EmployeeId.HasValue && !pinToEmployeeId.ContainsKey(du.Pin))
                    pinToEmployeeId[du.Pin] = du.EmployeeId.Value;
            }
            foreach (var emp in employees)
            {
                if (!string.IsNullOrEmpty(emp.EmployeeCode) && !pinToEmployeeId.ContainsKey(emp.EmployeeCode))
                    pinToEmployeeId[emp.EmployeeCode] = emp.Id;
            }

            var allPins = pinToEmployeeId.Keys.ToList();

            // Get attendances for the date (filter by Device.StoreId) — use Select projection.
            // AttendanceTime is stored in UTC; filter by VN-day UTC range so punches near
            // midnight VN fall into the correct calendar day.
            var attendances = await dbContext.AttendanceLogs
                .Where(a => a.Device != null && a.Device.StoreId == storeId
                    && a.AttendanceTime >= vnStart
                    && a.AttendanceTime < vnEnd
                    && allPins.Contains(a.PIN))
                .OrderBy(a => a.AttendanceTime)
                .Select(a => new { a.PIN, a.AttendanceTime, a.AttendanceState, a.Note })
                .ToListAsync();

            // Build attendance lookup by PIN for O(1) access
            var attendanceByPin = attendances.ToLookup(a => a.PIN);

            // Get leaves for the date (using EmployeeUserId linked to ApplicationUser)
            var employeeUserIds = employees
                .Where(e => e.ApplicationUserId.HasValue)
                .Select(e => e.ApplicationUserId!.Value)
                .ToList();
            
            var leaves = await dbContext.Leaves
                .Where(l => l.StoreId == storeId 
                    && l.StartDate <= targetDate 
                    && l.EndDate >= targetDate
                    && l.Status == LeaveStatus.Approved
                    && !l.CountAsWork
                    && employeeUserIds.Contains(l.EmployeeUserId))
                .Select(l => l.EmployeeUserId)
                .ToListAsync();

            // Build leave lookup as HashSet for O(1) check
            var leaveUserIds = new HashSet<Guid>(leaves);

            // Get work schedules for the date to check who is scheduled
            var employeeGuids = employees.Select(e => e.Id).ToList();
            var workSchedules = await dbContext.WorkSchedules
                .Include(ws => ws.Shift)
                .Where(ws => ws.StoreId == storeId
                    && ws.Date.Date == targetDate.Date
                    && ws.Deleted == null
                    && employeeGuids.Contains(ws.EmployeeUserId))
                .ToListAsync();

            // Build schedule lookup: EmployeeId -> all WorkSchedules for the day (multi-shift)
            var scheduleMap = workSchedules
                .GroupBy(ws => ws.EmployeeUserId)
                .ToDictionary(g => g.Key, g => g.ToList());

            // Load active salary profile (Benefit) for each employee — used as a
            // fallback when no WorkSchedule exists. Salary profile defines:
            //   • WeeklyOffDays (e.g. "Saturday,Sunday") → those weekdays are rest
            //     days and NOT counted as absent when employee doesn't show up.
            //   • CheckIn/CheckOut → default expected hours.
            // Any other working weekday with no check-in and no approved leave is
            // counted as "Vắng không phép".
            // EffectiveDate may carry a time component (e.g. created at 14:29:30 of the
            // same day). Treat assignment as effective for the WHOLE day, so compare against
            // end-of-day rather than 00:00. Same for EndDate inclusivity.
            var dayEndExclusive = targetDate.Date.AddDays(1);
            var activeBenefits = await dbContext.EmployeeBenefits
                .Include(eb => eb.Benefit)
                .Where(eb => employeeIds.Contains(eb.EmployeeId)
                    && eb.EffectiveDate < dayEndExclusive
                    && (eb.EndDate == null || eb.EndDate >= targetDate.Date))
                .OrderByDescending(eb => eb.EffectiveDate)
                .ToListAsync();
            var benefitByEmployeeId = activeBenefits
                .GroupBy(eb => eb.EmployeeId)
                .ToDictionary(g => g.Key, g => g.First().Benefit);

            // â”€â”€â”€ Load shift templates for "shifts in salary profile" fallback â”€â”€
            // Khi nhân viên không có WorkSchedule cho ngày, ta đối chiếu giờ
            // chấm vào với danh sách ca trong hồ sơ lương (Benefit.Description
            // dạng "shifts:Ca sáng, Ca chiều|...") để tính trễ/sớm chuẩn theo
            // tab "Tổng hợp theo ca" trên Flutter.
            var activeShiftTemplates = await dbContext.ShiftTemplates
                .Where(s => s.StoreId == storeId && s.IsActive)
                .Select(s => new ShiftInfo(
                    s.Id,
                    s.Name,
                    s.StartTime,
                    s.EndTime,
                    s.LateGraceMinutes,
                    s.EarlyLeaveGraceMinutes))
                .ToListAsync();
            static string NormalizeShiftName(string s) =>
                System.Text.RegularExpressions.Regex.Replace(
                    (s ?? string.Empty).Trim().ToLowerInvariant(), @"\s+", " ");
            var shiftByName = activeShiftTemplates
                .Where(s => !string.IsNullOrWhiteSpace(s.Name))
                .GroupBy(s => NormalizeShiftName(s.Name))
                .ToDictionary(g => g.Key, g => g.First());

            // Parse "k1:v1|k2:v2" description format used by Flutter salary UI.
            static string ParseDescField(string? description, string key)
            {
                if (string.IsNullOrWhiteSpace(description)) return string.Empty;
                foreach (var part in description.Split('|'))
                {
                    var idx = part.IndexOf(':');
                    if (idx <= 0) continue;
                    if (string.Equals(part[..idx].Trim(), key, StringComparison.OrdinalIgnoreCase))
                        return part[(idx + 1)..].Trim();
                }
                return string.Empty;
            }

            // Public holidays applicable to this date for this store.
            // A holiday applies if:
            //  • its exact Date == targetDate, OR
            //  • IsRecurring AND month/day match (annual holidays)
            //  • AND (StoreId == storeId OR StoreId IS NULL — null = global)
            //  • AND IsActive
            // EmployeeIds (comma-separated) optionally restricts the holiday to a subset.
            var allHolidays = await dbContext.Holidays
                .Where(h => h.IsActive
                    && (h.StoreId == null || h.StoreId == storeId))
                .Select(h => new { h.Date, h.IsRecurring, h.Name, h.EmployeeIds })
                .ToListAsync();
            var matchingHolidays = allHolidays
                .Where(h => h.Date.Date == targetDate.Date
                    || (h.IsRecurring && h.Date.Month == targetDate.Month && h.Date.Day == targetDate.Day))
                .ToList();
            var isHolidayToday = matchingHolidays.Any(h => string.IsNullOrWhiteSpace(h.EmployeeIds));
            // Per-employee holiday membership: if a holiday has EmployeeIds set,
            // only those employees are off on that holiday. EmployeeIds is stored either
            // as comma-separated values OR as a JSON array (legacy seeded data) — handle both.
            var holidayEmployeeIds = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var h in matchingHolidays.Where(h => !string.IsNullOrWhiteSpace(h.EmployeeIds)))
            {
                var raw = h.EmployeeIds!.Trim();
                if (raw.StartsWith('['))
                {
                    try
                    {
                        var arr = System.Text.Json.JsonSerializer.Deserialize<List<string>>(raw);
                        if (arr != null) foreach (var t in arr) holidayEmployeeIds.Add(t);
                    }
                    catch { /* fall back to CSV split below */ }
                }
                else
                {
                    foreach (var token in raw.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
                    {
                        holidayEmployeeIds.Add(token);
                    }
                }
            }
            logger.LogInformation("[DailyReport] Date={Date} StoreId={StoreId} Holidays(matching)={Count} isHolidayToday={IsHol} restrictedEmps={Emps}",
                targetDate.ToString("yyyy-MM-dd"), storeId, matchingHolidays.Count, isHolidayToday, holidayEmployeeIds.Count);

            // Map English DayOfWeek name (matches WeeklyOffDays storage format).
            var todayDayName = targetDate.DayOfWeek.ToString(); // e.g. "Saturday"

            // Build report data
            var reportItems = new List<DailyAttendanceItemDto>();
            var totalLate = 0;
            var totalEarlyLeave = 0;
            var totalOnTime = 0;
            var totalAbsent = 0;
            var totalOnLeave = 0;
            var totalNotScheduled = 0;
            var totalNoSalaryProfile = 0;

            // Default work hours: 8:30 AM - 6:00 PM (fallback if no shift template)
            var defaultExpectedStart = new TimeSpan(8, 30, 0);
            var defaultExpectedEnd = new TimeSpan(18, 0, 0);

            foreach (var employee in employees)
            {
                // Find all pins mapped to this employee (from DeviceUser + EmployeeCode)
                var employeePins = pinToEmployeeId
                    .Where(kv => kv.Value == employee.Id)
                    .Select(kv => kv.Key)
                    .ToList();

                // Use lookup instead of scanning entire list
                var empAttendances = employeePins.SelectMany(pin => attendanceByPin[pin]).ToList();
                var checkIn = empAttendances.Where(a => a.AttendanceState == AttendanceStates.CheckIn)
                    .OrderBy(a => a.AttendanceTime).FirstOrDefault();
                var checkOut = empAttendances.Where(a => a.AttendanceState == AttendanceStates.CheckOut)
                    .OrderByDescending(a => a.AttendanceTime).FirstOrDefault();

                // Check work schedule (may have multiple shifts per day)
                scheduleMap.TryGetValue(employee.Id, out var daySchedules);
                daySchedules ??= [];
                var workingSchedules = daySchedules.Where(s => !s.IsDayOff).ToList();
                var hasSchedule = daySchedules.Count > 0;
                var isDayOff = daySchedules.Any(s => s.IsDayOff) && workingSchedules.Count == 0;
                var schedule = workingSchedules.FirstOrDefault() ?? daySchedules.FirstOrDefault();

                // Fallback: when no explicit WorkSchedule exists for today, derive
                // the work-day rule from the employee's active salary profile
                // (Benefit.WeeklyOffDays). This ensures absent statistics work
                // even when admins haven't created daily schedules.
                benefitByEmployeeId.TryGetValue(employee.Id, out var benefit);
                var isWeeklyOffByBenefit = false;
                if (!hasSchedule && benefit != null && !string.IsNullOrWhiteSpace(benefit.WeeklyOffDays))
                {
                    var off = benefit.WeeklyOffDays
                        .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
                    isWeeklyOffByBenefit = off.Any(d => string.Equals(d, todayDayName, StringComparison.OrdinalIgnoreCase));
                }

                // Determine expected start/end from shift template, schedule
                // override, or fall back to the salary profile's CheckIn/CheckOut.
                var expectedStart = schedule?.StartTime
                    ?? schedule?.Shift?.StartTime
                    ?? (benefit?.CheckIn != null ? benefit.CheckIn.Value.ToTimeSpan() : defaultExpectedStart);
                var expectedEnd = schedule?.EndTime
                    ?? schedule?.Shift?.EndTime
                    ?? (benefit?.CheckOut != null ? benefit.CheckOut.Value.ToTimeSpan() : defaultExpectedEnd);
                int? lateGrace = schedule?.Shift?.LateGraceMinutes;
                int? earlyGrace = schedule?.Shift?.EarlyLeaveGraceMinutes;

                // Multi-shift: from WorkSchedule rows and/or salary profile shift list.
                List<ShiftInfo>? multiShiftAssignments = null;
                if (workingSchedules.Count > 1)
                {
                    multiShiftAssignments = workingSchedules
                        .Where(s => s.Shift != null)
                        .Select(s => new ShiftInfo(
                            s.ShiftId ?? s.Shift!.Id,
                            s.Shift!.Name ?? "",
                            s.StartTime ?? s.Shift.StartTime,
                            s.EndTime ?? s.Shift.EndTime,
                            s.Shift.LateGraceMinutes,
                            s.Shift.EarlyLeaveGraceMinutes))
                        .ToList();
                }
                else if (!hasSchedule && benefit != null)
                {
                    var shiftsStr = ParseDescField(benefit.Description, "shifts");
                    if (!string.IsNullOrWhiteSpace(shiftsStr))
                    {
                        var assignedShifts = shiftsStr
                            .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
                            .Select(NormalizeShiftName)
                            .Where(n => !string.IsNullOrEmpty(n) && shiftByName.ContainsKey(n))
                            .Select(n => shiftByName[n])
                            .ToList();
                        if (assignedShifts.Count > 0)
                        {
                            multiShiftAssignments = assignedShifts;
                            // Best-match ca chính (cho expectedStart/End mặc định khi chỉ có 1 punch)
                            if (checkIn != null)
                            {
                                var checkInVnMin = (int)checkIn.AttendanceTime.AddHours(7).TimeOfDay.TotalMinutes;
                                var bestDist = int.MaxValue;
                                var best = assignedShifts[0];
                                foreach (var s in assignedShifts)
                                {
                                    var startMin = (int)s.StartTime.TotalMinutes;
                                    var dist = Math.Abs(checkInVnMin - startMin);
                                    if (dist > 720) dist = 1440 - dist;
                                    if (dist < bestDist)
                                    {
                                        bestDist = dist;
                                        best = s;
                                    }
                                }
                                expectedStart = best.StartTime;
                                expectedEnd = best.EndTime;
                                lateGrace = best.LateGraceMinutes;
                                earlyGrace = best.EarlyLeaveGraceMinutes;
                            }
                        }
                    }
                }

                // Check if today is a public holiday for this employee.
                // A holiday applies if it has no EmployeeIds restriction (global)
                // OR the employee's id/code is in the restricted list.
                var isHolidayForEmp = isHolidayToday
                    || (holidayEmployeeIds.Count > 0 && (
                        holidayEmployeeIds.Contains(employee.Id.ToString())
                        || (!string.IsNullOrEmpty(employee.EmployeeCode) && holidayEmployeeIds.Contains(employee.EmployeeCode))));

                // Check if on leave — O(1) HashSet lookup
                var isOnLeave = employee.ApplicationUserId.HasValue && 
                    leaveUserIds.Contains(employee.ApplicationUserId.Value);
                
                // Calculate status
                var status = ReportLabels.Absent;
                var lateMinutes = 0;
                var earlyLeaveMinutes = 0;

                if (isHolidayForEmp && checkIn == null)
                {
                    // Public holiday and employee did not work → "Nghỉ lễ".
                    // If they DID check in on a holiday, fall through to normal
                    // attendance branches so OT/holiday-pay logic still applies.
                    status = ReportLabels.Holiday;
                    totalNotScheduled++;
                }
                else if (isOnLeave)
                {
                    status = ReportLabels.Leave;
                    totalOnLeave++;
                }
                else if (isDayOff || isWeeklyOffByBenefit)
                {
                    // Either an explicit WorkSchedule day-off, or a fixed weekly
                    // off day defined in the salary profile (Sat/Sun, etc.).
                    status = ReportLabels.DayOff;
                    totalNotScheduled++;
                }
                else if (!hasSchedule && benefit == null)
                {
                    // No WorkSchedule and no active salary profile — cannot infer working day.
                    status = ReportLabels.NoSalaryProfile;
                    totalNotScheduled++;
                    totalNoSalaryProfile++;
                }
                else if (checkIn != null)
                {
                    // Nếu nhân viên có nhiều ca trong hồ sơ lương, pair từng
                    // punch với ca gần nhất theo giờ và cộng dồn late/early.
                    if (multiShiftAssignments != null && multiShiftAssignments.Count > 1)
                    {
                        var sortedPunches = empAttendances
                            .OrderBy(a => a.AttendanceTime)
                            .ToList();
                        // Pair theo cặp (in, out) — odd index làm in, even+1 làm out.
                        var pairs = new List<(DateTime In, DateTime? Out)>();
                        for (int i = 0; i < sortedPunches.Count; i += 2)
                        {
                            var inT = sortedPunches[i].AttendanceTime;
                            DateTime? outT = (i + 1 < sortedPunches.Count)
                                ? sortedPunches[i + 1].AttendanceTime
                                : (DateTime?)null;
                            pairs.Add((inT, outT));
                        }

                        var totalShiftLate = 0;
                        var totalShiftEarly = 0;
                        foreach (var (inT, outT) in pairs)
                        {
                            var inVnMin = (int)inT.AddHours(7).TimeOfDay.TotalMinutes;
                            var bestDist = int.MaxValue;
                            ShiftInfo? bestShift = null;
                            foreach (var s in multiShiftAssignments)
                            {
                                var startMin = (int)s.StartTime.TotalMinutes;
                                var dist = Math.Abs(inVnMin - startMin);
                                if (dist > 720) dist = 1440 - dist;
                                if (dist < bestDist)
                                {
                                    bestDist = dist;
                                    bestShift = s;
                                }
                            }
                            if (bestShift == null) continue;
                            var sStart = bestShift.StartTime;
                            var sEnd = bestShift.EndTime;
                            int sLateGrace = bestShift.LateGraceMinutes;
                            int sEarlyGrace = bestShift.EarlyLeaveGraceMinutes;

                            var inTime = inT.AddHours(7).TimeOfDay;
                            if (inTime > sStart + TimeSpan.FromMinutes(sLateGrace))
                            {
                                totalShiftLate += (int)(inTime - sStart).TotalMinutes;
                            }
                            if (outT.HasValue)
                            {
                                var outTime = outT.Value.AddHours(7).TimeOfDay;
                                if (outTime < sEnd - TimeSpan.FromMinutes(sEarlyGrace))
                                {
                                    totalShiftEarly += (int)(sEnd - outTime).TotalMinutes;
                                }
                            }
                        }

                        lateMinutes = totalShiftLate;
                        earlyLeaveMinutes = totalShiftEarly;
                        if (lateMinutes > 0 && earlyLeaveMinutes > 0)
                        {
                            status = ReportLabels.LateAndEarly;
                            totalLate++;
                            totalEarlyLeave++;
                        }
                        else if (lateMinutes > 0)
                        {
                            status = ReportLabels.Late;
                            totalLate++;
                        }
                        else if (earlyLeaveMinutes > 0)
                        {
                            status = ReportLabels.Early;
                            totalEarlyLeave++;
                        }
                        else
                        {
                            status = ReportLabels.OnTime;
                            totalOnTime++;
                        }
                    }
                    else
                    {
                        // AttendanceTime is stored as UTC. Convert to VN (UTC+7) before comparing with shift times.
                        var checkInTime = checkIn.AttendanceTime.AddHours(7).TimeOfDay;
                        var lateGraceMin = TimeSpan.FromMinutes(lateGrace ?? 0);
                        if (checkInTime > expectedStart + lateGraceMin)
                        {
                            lateMinutes = (int)(checkInTime - expectedStart).TotalMinutes;
                            status = ReportLabels.Late;
                            totalLate++;
                        }
                        else
                        {
                            status = ReportLabels.OnTime;
                            totalOnTime++;
                        }

                        if (checkOut != null)
                        {
                            var checkOutTime = checkOut.AttendanceTime.AddHours(7).TimeOfDay;
                            var earlyGraceMin = TimeSpan.FromMinutes(earlyGrace ?? 0);
                            if (checkOutTime < expectedEnd - earlyGraceMin)
                            {
                                earlyLeaveMinutes = (int)(expectedEnd - checkOutTime).TotalMinutes;
                                if (status == ReportLabels.OnTime)
                                {
                                    status = ReportLabels.Early;
                                }
                                else
                                {
                                    status += " + Về sớm";
                                }
                                totalEarlyLeave++;
                            }
                        }
                    }
                }
                else
                {
                    // Today is a working day (per WorkSchedule or salary
                    // profile), no check-in, no approved leave → vắng không phép.
                    status = ReportLabels.AbsentUnexcused;
                    totalAbsent++;
                }

                var workedMinutes = ReportsExportHelpers.WorkedMinutesVn(
                    checkIn?.AttendanceTime, checkOut?.AttendanceTime);

                reportItems.Add(new DailyAttendanceItemDto
                {
                    EmployeeId = employee.Id,
                    EmployeeCode = employee.EmployeeCode,
                    EmployeeName = $"{employee.LastName} {employee.FirstName}".Trim(),
                    DepartmentName = employee.Department ?? "N/A",
                    CheckInTime = checkIn?.AttendanceTime,
                    CheckOutTime = checkOut?.AttendanceTime,
                    LateMinutes = lateMinutes,
                    EarlyLeaveMinutes = earlyLeaveMinutes,
                    WorkedMinutes = workedMinutes,
                    Status = status,
                    Note = ReportLabels.ResolveAttendanceNote(
                        status, checkIn?.Note ?? checkOut?.Note)
                });
            }

            var scheduledCount = employees.Count - totalNotScheduled;
            // Present = nhân viên có check-in (đúng giờ + đi muộn). "Về sớm" là sub-flag,
            // không cộng thêm vào Present để tránh đếm 2 lần người đi muộn-về sớm.
            var totalPresent = totalOnTime + totalLate;
            // Mẫu số của tỷ lệ chấm công bỏ qua người nghỉ phép hợp lệ để phản ánh
            // đúng mức độ "vắng ngoài dự kiến".
            var rateDenominator = scheduledCount - totalOnLeave;
            var report = new DailyAttendanceReportDto
            {
                Date = targetDate,
                TotalEmployees = employees.Count,
                Present = totalPresent,
                OnTime = totalOnTime,
                Late = totalLate,
                EarlyLeave = totalEarlyLeave,
                Absent = totalAbsent,
                OnLeave = totalOnLeave,
                NoSalaryProfile = totalNoSalaryProfile,
                AttendanceRate = rateDenominator > 0
                    ? Math.Round((double)totalPresent / rateDenominator * 100, 2)
                    : 0,
                Items = reportItems.OrderBy(i => i.DepartmentName).ThenBy(i => i.EmployeeCode).ToList()
            };

            return Ok(AppResponse<DailyAttendanceReportDto>.Success(report));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error generating daily attendance report");
            return StatusCode(500, AppResponse<DailyAttendanceReportDto>.Fail("Error generating report"));
        }
    }

    #endregion

    #region Monthly Summary Report

    /// <summary>
    /// Get monthly attendance summary report
    /// </summary>
    [HttpGet("attendance/monthly")]
    [RequireAnyModulePermission(ModulePermissionAction.View, "AttendanceReport", "AttendanceSummary", "AttendanceByShift", "Attendance")]
    public async Task<ActionResult<AppResponse<MonthlyAttendanceReportDto>>> GetMonthlyAttendanceReport(
        [FromQuery] int? year = null,
        [FromQuery] int? month = null,
        [FromQuery] string? department = null,
        [FromQuery] string? employeeCodes = null,
        [FromQuery] Guid? branchId = null,
        [FromQuery] bool includeChildBranches = true)
    {
        try
        {
            var targetYear = year ?? DateTime.UtcNow.AddHours(7).Year;
            var targetMonth = month ?? DateTime.UtcNow.AddHours(7).Month;
            var storeId = RequiredStoreId;

            // VN calendar month boundaries (local) + UTC query window.
            var startDate = new DateTime(targetYear, targetMonth, 1);
            var endDate = startDate.AddMonths(1).AddDays(-1);
            var utcStart = startDate.AddHours(-7);
            var utcEnd = startDate.AddMonths(1).AddHours(-7);

            var employeesQuery = dbContext.Employees
                .Where(e => e.StoreId == storeId && e.Deleted == null);

            employeesQuery = await FilterEmployeesQueryAsync(
                employeesQuery, storeId, department, branchId, includeChildBranches, employeeCodes);

            var employees = await employeesQuery.ToListAsync();

            var employeePins = employees.Select(e => e.EmployeeCode).ToList();

            // AttendanceLogs stored in UTC — filter by VN-month UTC range.
            var rawAttendances = await dbContext.AttendanceLogs
                .Where(a => a.Device != null && a.Device.StoreId == storeId
                    && a.AttendanceTime >= utcStart
                    && a.AttendanceTime < utcEnd
                    && employeePins.Contains(a.PIN))
                .Select(a => new { a.PIN, a.AttendanceTime, a.AttendanceState })
                .ToListAsync();

            // Project once to VN-local time so all Date/TimeOfDay compares are correct.
            var attendances = rawAttendances
                .Select(a => new { a.PIN, VnTime = a.AttendanceTime.AddHours(7), a.AttendanceState })
                .ToList();

            // Build attendance lookup by PIN for O(1) access
            var attendanceByPin = attendances.ToLookup(a => a.PIN);

            // Get leaves for the month
            var employeeUserIds = employees
                .Where(e => e.ApplicationUserId.HasValue)
                .Select(e => e.ApplicationUserId!.Value)
                .ToList();
            
            var leaves = await dbContext.Leaves
                .Where(l => l.StoreId == storeId 
                    && l.StartDate <= endDate 
                    && l.EndDate >= startDate
                    && l.Status == LeaveStatus.Approved
                    && !l.CountAsWork
                    && employeeUserIds.Contains(l.EmployeeUserId))
                .Select(l => new { l.EmployeeUserId, l.StartDate, l.EndDate })
                .ToListAsync();

            // Build leave lookup by EmployeeUserId for O(1) access
            var leavesByUserId = leaves.ToLookup(l => l.EmployeeUserId);

            // Get holidays for the month
            var holidays = await dbContext.Holidays
                .Where(h => h.StoreId == storeId && h.Date >= startDate && h.Date <= endDate)
                .Select(h => h.Date)
                .ToListAsync();

            // Calculate working days (excluding weekends and holidays)
            var workingDays = 0;
            for (var d = startDate; d <= endDate; d = d.AddDays(1))
            {
                if (d.DayOfWeek != DayOfWeek.Saturday && d.DayOfWeek != DayOfWeek.Sunday && !holidays.Contains(d))
                {
                    workingDays++;
                }
            }

            var reportItems = new List<MonthlyAttendanceItemDto>();
            var totalNoSalaryProfile = 0;

            var employeeIds = employees.Select(e => e.Id).ToList();
            var monthEndExclusive = endDate.Date.AddDays(1);
            var activeBenefits = await dbContext.EmployeeBenefits
                .Include(eb => eb.Benefit)
                .Where(eb => employeeIds.Contains(eb.EmployeeId)
                    && eb.EffectiveDate < monthEndExclusive
                    && (eb.EndDate == null || eb.EndDate >= startDate.Date))
                .OrderByDescending(eb => eb.EffectiveDate)
                .ToListAsync();
            var benefitByEmployeeId = activeBenefits
                .GroupBy(eb => eb.EmployeeId)
                .ToDictionary(g => g.Key, g => g.First().Benefit);

            // Default late threshold: 8:30 AM
            var lateThreshold = new TimeSpan(8, 30, 0);

            foreach (var employee in employees)
            {
                // O(1) lookup instead of scanning entire list
                var empAttendances = attendanceByPin[employee.EmployeeCode].ToList();
                
                // Get leaves for this employee — O(1) lookup (ILookup returns empty for missing keys)
                var empLeaveUserId = employee.ApplicationUserId ?? Guid.Empty;
                var empLeaves = leavesByUserId[empLeaveUserId];

                // Count working days attended (VN-local dates)
                var daysPresent = empAttendances
                    .Select(a => a.VnTime.Date)
                    .Distinct()
                    .Count();

                // Count late arrivals using VN local TimeOfDay
                var lateDays = empAttendances
                    .Where(a => a.AttendanceState == AttendanceStates.CheckIn)
                    .GroupBy(a => a.VnTime.Date)
                    .Count(g => g.OrderBy(a => a.VnTime).First().VnTime.TimeOfDay > lateThreshold);

                // Count leave days for this employee
                var leaveDays = 0;
                foreach (var leave in empLeaves)
                {
                    var leaveStart = leave.StartDate < startDate ? startDate : leave.StartDate;
                    var leaveEnd = leave.EndDate > endDate ? endDate : leave.EndDate;
                    leaveDays += (int)(leaveEnd - leaveStart).TotalDays + 1;
                }

                // Calculate total worked minutes — group by VN date, diff in VN times
                var totalWorkedMinutes = 0;
                var groupedByDate = empAttendances.GroupBy(a => a.VnTime.Date);
                foreach (var dayGroup in groupedByDate)
                {
                    var dayCheckIn = dayGroup.Where(a => a.AttendanceState == AttendanceStates.CheckIn)
                        .OrderBy(a => a.VnTime).FirstOrDefault();
                    var dayCheckOut = dayGroup.Where(a => a.AttendanceState == AttendanceStates.CheckOut)
                        .OrderByDescending(a => a.VnTime).FirstOrDefault();

                    if (dayCheckIn != null && dayCheckOut != null)
                    {
                        totalWorkedMinutes += (int)(dayCheckOut.VnTime - dayCheckIn.VnTime).TotalMinutes;
                    }
                }

                var absentDays = workingDays - daysPresent - leaveDays;
                if (absentDays < 0) absentDays = 0;

                var hasSalaryProfile = benefitByEmployeeId.ContainsKey(employee.Id);
                if (!hasSalaryProfile) totalNoSalaryProfile++;

                reportItems.Add(new MonthlyAttendanceItemDto
                {
                    EmployeeId = employee.Id,
                    EmployeeCode = employee.EmployeeCode,
                    EmployeeName = $"{employee.LastName} {employee.FirstName}".Trim(),
                    DepartmentName = employee.Department ?? "N/A",
                    HasSalaryProfile = hasSalaryProfile,
                    Note = hasSalaryProfile ? null : ReportLabels.SalarySetupReminder,
                    TotalDaysWorked = daysPresent,
                    TotalLateDays = lateDays,
                    TotalLeaveDays = leaveDays,
                    TotalAbsentDays = absentDays,
                    TotalWorkedHours = Math.Round(totalWorkedMinutes / 60.0, 2),
                    AttendanceRate = workingDays > 0 
                        ? Math.Round((double)daysPresent / workingDays * 100, 2) 
                        : 0
                });
            }

            var report = new MonthlyAttendanceReportDto
            {
                Year = targetYear,
                Month = targetMonth,
                WorkingDays = workingDays,
                TotalEmployees = employees.Count,
                NoSalaryProfile = totalNoSalaryProfile,
                Items = reportItems.OrderBy(i => i.DepartmentName).ThenBy(i => i.EmployeeCode).ToList()
            };

            return Ok(AppResponse<MonthlyAttendanceReportDto>.Success(report));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error generating monthly attendance report");
            return StatusCode(500, AppResponse<MonthlyAttendanceReportDto>.Fail("Error generating report"));
        }
    }

    #endregion

    #region Employee Attendance Report

    /// <summary>
    /// Get individual employee attendance report
    /// </summary>
    [HttpGet("attendance/employee/{employeeId}")]
    [RequireAnyModulePermission(ModulePermissionAction.View, "AttendanceReport", "AttendanceSummary", "AttendanceByShift", "Attendance")]
    public async Task<ActionResult<AppResponse<EmployeeAttendanceReportDto>>> GetEmployeeAttendanceReport(
        Guid employeeId,
        [FromQuery] DateTime? startDate = null,
        [FromQuery] DateTime? endDate = null)
    {
        try
        {
            var storeId = RequiredStoreId;
            var start = startDate ?? DateTime.Today.AddMonths(-1);
            var end = endDate ?? DateTime.Today;

            var employee = await dbContext.Employees
                .FirstOrDefaultAsync(e => e.Id == employeeId && e.StoreId == storeId);

            if (employee == null)
            {
                return NotFound(AppResponse<EmployeeAttendanceReportDto>.Fail("Employee not found"));
            }

            var attendances = await dbContext.AttendanceLogs
                .Where(a => a.Device != null && a.Device.StoreId == storeId 
                    && a.PIN == employee.EmployeeCode
                    && a.AttendanceTime >= start 
                    && a.AttendanceTime <= end.AddDays(1))
                .OrderBy(a => a.AttendanceTime)
                .Select(a => new { a.AttendanceTime, a.AttendanceState, a.Note })
                .ToListAsync();

            // Get leaves
            var empLeaves = new List<(DateTime StartDate, DateTime EndDate)>();
            if (employee.ApplicationUserId.HasValue)
            {
                empLeaves = await dbContext.Leaves
                    .Where(l => l.EmployeeUserId == employee.ApplicationUserId.Value
                        && l.StartDate <= end 
                        && l.EndDate >= start
                        && l.Status == LeaveStatus.Approved
                        && !l.CountAsWork)
                    .Select(l => new ValueTuple<DateTime, DateTime>(l.StartDate, l.EndDate))
                    .ToListAsync();
            }

            var holidays = await dbContext.Holidays
                .Where(h => h.StoreId == storeId && h.Date >= start && h.Date <= end)
                .Select(h => h.Date)
                .ToListAsync();

            // Build daily records
            var dailyRecords = new List<EmployeeAttendanceDayDto>();
            var totalWorkedMinutes = 0;
            var totalLateDays = 0;
            var totalEarlyLeaveDays = 0;
            var totalPresentDays = 0;
            var totalAbsentDays = 0;
            var totalLeaveDays = 0;

            // Default times
            var lateThreshold = new TimeSpan(8, 30, 0);
            var earlyLeaveThreshold = new TimeSpan(18, 0, 0);

            for (var d = start; d <= end; d = d.AddDays(1))
            {
                // Skip weekends
                if (d.DayOfWeek == DayOfWeek.Saturday || d.DayOfWeek == DayOfWeek.Sunday)
                {
                    continue;
                }

                var isHoliday = holidays.Contains(d);
                var isOnLeave = empLeaves.Any(l => d >= l.StartDate && d <= l.EndDate);

                var dayAttendances = attendances.Where(a => a.AttendanceTime.Date == d).ToList();
                var checkIn = dayAttendances.Where(a => a.AttendanceState == AttendanceStates.CheckIn)
                    .OrderBy(a => a.AttendanceTime).FirstOrDefault();
                var checkOut = dayAttendances.Where(a => a.AttendanceState == AttendanceStates.CheckOut)
                    .OrderByDescending(a => a.AttendanceTime).FirstOrDefault();

                var status = ReportLabels.Absent;
                var workedMinutes = 0;
                var isLate = false;
                var isEarlyLeave = false;

                if (isHoliday)
                {
                    status = ReportLabels.Holiday;
                }
                else if (isOnLeave)
                {
                    status = ReportLabels.Leave;
                    totalLeaveDays++;
                }
                else if (checkIn != null)
                {
                    totalPresentDays++;
                    var checkInTime = checkIn.AttendanceTime.AddHours(7).TimeOfDay;
                    
                    if (checkInTime > lateThreshold)
                    {
                        isLate = true;
                        totalLateDays++;
                            status = ReportLabels.Late;
                    }
                    else
                    {
                        status = ReportLabels.OnTime;
                    }

                    if (checkOut != null)
                    {
                        workedMinutes = ReportsExportHelpers.WorkedMinutesVn(
                            checkIn.AttendanceTime, checkOut.AttendanceTime);
                        totalWorkedMinutes += workedMinutes;
                        
                        if (checkOut.AttendanceTime.AddHours(7).TimeOfDay < earlyLeaveThreshold)
                        {
                            isEarlyLeave = true;
                            totalEarlyLeaveDays++;
                            if (isLate) status += " + Về sớm";
                            else status = ReportLabels.Early;
                        }
                    }
                }
                else if (!isHoliday && !isOnLeave)
                {
                    totalAbsentDays++;
                }

                dailyRecords.Add(new EmployeeAttendanceDayDto
                {
                    Date = d,
                    DayOfWeek = GetDayOfWeekVN(d.DayOfWeek),
                    CheckInTime = checkIn?.AttendanceTime,
                    CheckOutTime = checkOut?.AttendanceTime,
                    WorkedMinutes = workedMinutes,
                    IsLate = isLate,
                    IsEarlyLeave = isEarlyLeave,
                    IsHoliday = isHoliday,
                    IsOnLeave = isOnLeave,
                    Status = status
                });
            }

            var workingDays = dailyRecords.Count(d => !d.IsHoliday);

            var report = new EmployeeAttendanceReportDto
            {
                EmployeeId = employee.Id,
                EmployeeCode = employee.EmployeeCode,
                EmployeeName = $"{employee.LastName} {employee.FirstName}".Trim(),
                DepartmentName = employee.Department ?? "N/A",
                Position = employee.Position ?? "N/A",
                StartDate = start,
                EndDate = end,
                TotalWorkingDays = workingDays,
                TotalPresentDays = totalPresentDays,
                TotalAbsentDays = totalAbsentDays,
                TotalLeaveDays = totalLeaveDays,
                TotalLateDays = totalLateDays,
                TotalEarlyLeaveDays = totalEarlyLeaveDays,
                TotalWorkedHours = Math.Round(totalWorkedMinutes / 60.0, 2),
                AttendanceRate = workingDays > 0 
                    ? Math.Round((double)totalPresentDays / workingDays * 100, 2) 
                    : 0,
                DailyRecords = dailyRecords
            };

            return Ok(AppResponse<EmployeeAttendanceReportDto>.Success(report));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error generating employee attendance report");
            return StatusCode(500, AppResponse<EmployeeAttendanceReportDto>.Fail("Error generating report"));
        }
    }

    #endregion

    #region Late/Early Report

    /// <summary>
    /// Get late arrival and early leaving report
    /// </summary>
    [HttpGet("late-early")]
    [RequireAnyModulePermission(ModulePermissionAction.View, "AttendanceReport", "AttendanceSummary", "AttendanceByShift", "Attendance")]
    public async Task<ActionResult<AppResponse<LateEarlyReportDto>>> GetLateEarlyReport(
        [FromQuery] DateTime? startDate = null,
        [FromQuery] DateTime? endDate = null,
        [FromQuery] string? department = null,
        [FromQuery] string? employeeCodes = null,
        [FromQuery] Guid? branchId = null,
        [FromQuery] bool includeChildBranches = true)
    {
        try
        {
            var storeId = RequiredStoreId;
            var start = startDate ?? DateTime.Today.AddMonths(-1);
            var end = endDate ?? DateTime.Today;

            var employeesQuery = dbContext.Employees
                .Where(e => e.StoreId == storeId && e.Deleted == null);

            employeesQuery = await FilterEmployeesQueryAsync(
                employeesQuery, storeId, department, branchId, includeChildBranches, employeeCodes);

            var employees = await employeesQuery.ToListAsync();

            // â”€â”€â”€ Loại bỏ NV chưa thiết lập bảng lương (giống tab "Tổng hợp theo ca") â”€
            // Tab Flutter chỉ tính trễ/sớm cho NV nằm trong SalaryProfile thuộc
            // store hiện tại (BenefitsController.GetAllProfiles filter Benefit.StoreId).
            var salaryProfileEmpIds = await (
                from eb in dbContext.Set<EmployeeBenefit>()
                join b in dbContext.Set<Benefit>() on eb.BenefitId equals b.Id
                where b.StoreId == storeId
                select eb.EmployeeId
            ).Distinct().ToListAsync();
            var salaryProfileEmpIdSet = salaryProfileEmpIds.ToHashSet();
            employees = employees.Where(e => salaryProfileEmpIdSet.Contains(e.Id)).ToList();

            var employeePins = employees.Select(e => e.EmployeeCode).ToList();
            var employeeIdSet = employees.Select(e => e.Id).ToHashSet();

            // â”€â”€â”€ Load shift templates (active in this store) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
            // Mirror logic của tab "Tổng hợp theo ca" (attendance_by_shift_tab.dart):
            // mỗi punch tìm ca phù hợp dựa trên thời điểm chấm vào, áp dụng
            // grace period rồi mới tính trễ/sớm.
            var shiftTemplates = await dbContext.ShiftTemplates
                .Where(s => s.StoreId == storeId && s.IsActive)
                .Select(s => new
                {
                    s.Id,
                    s.StartTime,
                    s.EndTime,
                    s.LateGraceMinutes,
                    s.EarlyLeaveGraceMinutes,
                })
                .ToListAsync();

            // â”€â”€â”€ Load shift salary levels → empId → assigned shift ids â”€â”€â”€â”€â”€â”€
            var shiftSalaryLevels = await dbContext.Set<ShiftSalaryLevel>()
                .Select(l => new { l.ShiftTemplateId, l.EmployeeIds })
                .ToListAsync();
            var empIdToShiftIds = new Dictionary<Guid, List<Guid>>();
            foreach (var lvl in shiftSalaryLevels)
            {
                if (string.IsNullOrWhiteSpace(lvl.EmployeeIds)) continue;
                List<string>? ids = null;
                try
                {
                    ids = System.Text.Json.JsonSerializer.Deserialize<List<string>>(lvl.EmployeeIds);
                }
                catch { /* malformed JSON — bỏ qua dòng này */ }
                if (ids == null) continue;
                foreach (var raw in ids)
                {
                    if (!Guid.TryParse(raw, out var empGuid)) continue;
                    if (!employeeIdSet.Contains(empGuid)) continue;
                    if (!empIdToShiftIds.TryGetValue(empGuid, out var list))
                    {
                        list = new List<Guid>();
                        empIdToShiftIds[empGuid] = list;
                    }
                    if (!list.Contains(lvl.ShiftTemplateId)) list.Add(lvl.ShiftTemplateId);
                }
            }

            var attendances = await dbContext.AttendanceLogs
                .Where(a => a.Device != null && a.Device.StoreId == storeId
                    && a.AttendanceTime >= start
                    && a.AttendanceTime <= end.AddDays(1)
                    && employeePins.Contains(a.PIN))
                .Select(a => new { a.PIN, a.AttendanceTime, a.AttendanceState })
                .ToListAsync();
            var attendanceByPin = attendances.ToLookup(a => a.PIN);

            var reportItems = new List<LateEarlyItemDto>();
            var totalLateCount = 0;
            var totalEarlyCount = 0;
            var totalLateMinutes = 0;
            var totalEarlyMinutes = 0;

            foreach (var employee in employees)
            {
                var empAttendances = attendanceByPin[employee.EmployeeCode].ToList();
                if (empAttendances.Count == 0) continue;

                // Candidate shift templates: ca được gán riêng nếu có,
                // không thì duyệt toàn bộ ca trong store (giống fallback Flutter).
                var candidateIds = empIdToShiftIds.TryGetValue(employee.Id, out var assigned) && assigned.Count > 0
                    ? assigned
                    : shiftTemplates.Select(s => s.Id).ToList();
                var candidateShifts = shiftTemplates.Where(s => candidateIds.Contains(s.Id)).ToList();

                var groupedByDate = empAttendances.GroupBy(a => a.AttendanceTime.Date);
                var lateCount = 0;
                var earlyCount = 0;
                var lateMins = 0;
                var earlyMins = 0;

                foreach (var dayGroup in groupedByDate)
                {
                    var dayPunches = dayGroup.OrderBy(a => a.AttendanceTime).ToList();
                    var ins = dayPunches.Where(a => a.AttendanceState == AttendanceStates.CheckIn).ToList();
                    var outs = dayPunches.Where(a => a.AttendanceState == AttendanceStates.CheckOut).ToList();

                    // Pair (in, out): ưu tiên dùng AttendanceState; nếu không
                    // đủ thông tin thì rơi về ghép theo thứ tự chronological.
                    var pairs = new List<(DateTime? In, DateTime? Out)>();
                    if (ins.Count > 0 && outs.Count > 0 && (ins.Count + outs.Count) == dayPunches.Count)
                    {
                        var remainingOuts = new List<DateTime>(outs.Select(o => o.AttendanceTime));
                        foreach (var inP in ins)
                        {
                            var idx = remainingOuts.FindIndex(o => o >= inP.AttendanceTime);
                            if (idx >= 0)
                            {
                                pairs.Add((inP.AttendanceTime, remainingOuts[idx]));
                                remainingOuts.RemoveAt(idx);
                            }
                            else pairs.Add((inP.AttendanceTime, null));
                        }
                        foreach (var o in remainingOuts) pairs.Add((null, o));
                    }
                    else
                    {
                        for (int i = 0; i < dayPunches.Count; i += 2)
                        {
                            var inT = dayPunches[i].AttendanceTime;
                            DateTime? outT = (i + 1 < dayPunches.Count) ? dayPunches[i + 1].AttendanceTime : null;
                            pairs.Add((inT, outT));
                        }
                    }

                    foreach (var (punchIn, punchOut) in pairs)
                    {
                        // Mirror tab "Tổng hợp theo ca": chỉ tính trễ/sớm khi pair
                        // có ĐỦ cả IN và OUT (attendanceMode='both' mặc định).
                        // Pair thiếu 1 vế → coi là "thiếu chấm công", không
                        // cộng vào trễ/sớm để tránh số ảo (vd. 683p do match
                        // nhầm ca cho 1 punch lẻ).
                        if (punchIn == null || punchOut == null) continue;

                        var refTime = punchIn ?? punchOut;
                        if (refTime == null) continue;
                        var refMin = refTime.Value.Hour * 60 + refTime.Value.Minute;

                        // Tìm ca khớp nhất: dùng wrap-around distance (giống Flutter
                        // _findMatchingShift). Nếu best > 180 phút thì fallback duyệt
                        // toàn bộ ca trong store; nếu vẫn > 180 thì BỎ QUA pair này.
                        static int WrapDist(int refM, int startM)
                        {
                            var d = Math.Abs(refM - startM);
                            if (d > 720) d = 1440 - d;
                            return d;
                        }
                        var matched = candidateShifts
                            .Select(s => new { Shift = s, Diff = WrapDist(refMin, (int)s.StartTime.TotalMinutes) })
                            .OrderBy(x => x.Diff)
                            .FirstOrDefault();
                        if (matched == null || matched.Diff > 180)
                        {
                            // Nếu nhân viên đã được gán ca cụ thể, KHÔNG fallback sang ca
                            // khác. Một punch cách xa ca được gán → coi là punch lạc
                            // (vd. NV ca đêm chấm vào lúc 14:33 không nên bị tính trễ
                            // 93p theo "Ca chiều"). Chỉ fallback khi nhân viên CHƯA
                            // được gán ca nào.
                            var hasAssignedShifts = empIdToShiftIds.TryGetValue(employee.Id, out var assignedList)
                                && assignedList.Count > 0;
                            if (hasAssignedShifts) continue;

                            var fallback = shiftTemplates
                                .Select(s => new { Shift = s, Diff = WrapDist(refMin, (int)s.StartTime.TotalMinutes) })
                                .OrderBy(x => x.Diff)
                                .FirstOrDefault();
                            if (fallback == null || fallback.Diff > 180) continue;
                            matched = fallback;
                        }
                        var shift = matched.Shift;
                        var shiftStartMin = (int)shift.StartTime.TotalMinutes;
                        var shiftEndMin = (int)shift.EndTime.TotalMinutes;
                        var isCross = shiftStartMin > shiftEndMin;

                        // Late
                        if (punchIn != null)
                        {
                            var pinMin = punchIn.Value.Hour * 60 + punchIn.Value.Minute;
                            int lateCalc = 0;
                            if (isCross)
                            {
                                if (pinMin >= shiftStartMin) lateCalc = pinMin - shiftStartMin;
                                else if (pinMin < shiftEndMin) lateCalc = (1440 - shiftStartMin) + pinMin;
                            }
                            else if (pinMin > shiftStartMin) lateCalc = pinMin - shiftStartMin;
                            if (lateCalc <= shift.LateGraceMinutes) lateCalc = 0;
                            if (lateCalc > 0)
                            {
                                lateCount++;
                                lateMins += lateCalc;
                            }
                        }

                        // Early
                        if (punchOut != null)
                        {
                            var poutMin = punchOut.Value.Hour * 60 + punchOut.Value.Minute;
                            int earlyCalc = 0;
                            if (isCross)
                            {
                                if (poutMin <= shiftEndMin) earlyCalc = shiftEndMin - poutMin;
                                else if (poutMin >= shiftStartMin) earlyCalc = (1440 - poutMin) + shiftEndMin;
                            }
                            else if (poutMin < shiftEndMin) earlyCalc = shiftEndMin - poutMin;
                            if (earlyCalc <= shift.EarlyLeaveGraceMinutes) earlyCalc = 0;
                            if (earlyCalc > 0)
                            {
                                earlyCount++;
                                earlyMins += earlyCalc;
                            }
                        }
                    }
                }

                if (lateCount > 0 || earlyCount > 0)
                {
                    reportItems.Add(new LateEarlyItemDto
                    {
                        EmployeeId = employee.Id,
                        EmployeeCode = employee.EmployeeCode,
                        EmployeeName = $"{employee.LastName} {employee.FirstName}".Trim(),
                        DepartmentName = employee.Department ?? "N/A",
                        LateCount = lateCount,
                        TotalLateMinutes = lateMins,
                        EarlyLeaveCount = earlyCount,
                        TotalEarlyMinutes = earlyMins
                    });
                    totalLateCount += lateCount;
                    totalEarlyCount += earlyCount;
                    totalLateMinutes += lateMins;
                    totalEarlyMinutes += earlyMins;
                }
            }

            var report = new LateEarlyReportDto
            {
                StartDate = start,
                EndDate = end,
                TotalEmployees = employees.Count,
                EmployeesWithIssues = reportItems.Count,
                TotalLateCount = totalLateCount,
                TotalLateMinutes = totalLateMinutes,
                TotalEarlyLeaveCount = totalEarlyCount,
                TotalEarlyMinutes = totalEarlyMinutes,
                Items = reportItems.OrderByDescending(i => i.LateCount + i.EarlyLeaveCount).ToList()
            };

            return Ok(AppResponse<LateEarlyReportDto>.Success(report));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error generating late/early report");
            return StatusCode(500, AppResponse<LateEarlyReportDto>.Fail("Error generating report"));
        }
    }

    #endregion

    #region Department Summary Report

    /// <summary>
    /// Get department summary report
    /// </summary>
    [HttpGet("department-summary")]
    [RequireAnyModulePermission(ModulePermissionAction.View, "AttendanceReport", "AttendanceSummary", "AttendanceByShift", "Attendance")]
    public async Task<ActionResult<AppResponse<DepartmentSummaryReportDto>>> GetDepartmentSummaryReport(
        [FromQuery] int? year = null,
        [FromQuery] int? month = null)
    {
        try
        {
            var targetYear = year ?? DateTime.Now.Year;
            var targetMonth = month ?? DateTime.Now.Month;
            var storeId = RequiredStoreId;

            var startDate = new DateTime(targetYear, targetMonth, 1);
            var endDate = startDate.AddMonths(1).AddDays(-1);

            var employees = await dbContext.Employees
                .Where(e => e.StoreId == storeId && e.Deleted == null)
                .ToListAsync();

            var employeeCodes = employees.Select(e => e.EmployeeCode).ToList();

            var attendances = await dbContext.AttendanceLogs
                .Where(a => a.Device != null && a.Device.StoreId == storeId 
                    && a.AttendanceTime >= startDate 
                    && a.AttendanceTime <= endDate.AddDays(1)
                    && employeeCodes.Contains(a.PIN))
                .Select(a => new { a.PIN, a.AttendanceTime, a.AttendanceState })
                .ToListAsync();

            // Build attendance lookup by PIN for O(1) access
            var attendanceByPin = attendances.ToLookup(a => a.PIN);

            var holidays = await dbContext.Holidays
                .Where(h => h.StoreId == storeId && h.Date >= startDate && h.Date <= endDate)
                .Select(h => h.Date)
                .ToListAsync();

            // Calculate working days
            var workingDays = 0;
            for (var d = startDate; d <= endDate; d = d.AddDays(1))
            {
                if (d.DayOfWeek != DayOfWeek.Saturday && d.DayOfWeek != DayOfWeek.Sunday && !holidays.Contains(d))
                {
                    workingDays++;
                }
            }

            // Group employees by department
            var departments = employees
                .GroupBy(e => e.Department ?? "Chưa phân bổ")
                .ToList();

            var reportItems = new List<DepartmentSummaryItemDto>();

            // Default late threshold
            var lateThreshold = new TimeSpan(8, 30, 0);

            foreach (var dept in departments)
            {
                var deptEmployees = dept.ToList();
                var totalWorkedMinutes = 0;
                var lateCount = 0;
                var attendedDays = 0;

                foreach (var emp in deptEmployees)
                {
                    // O(1) lookup instead of scanning
                    var empAtts = attendanceByPin[emp.EmployeeCode].ToList();
                    var groupedByDate = empAtts.GroupBy(a => a.AttendanceTime.AddHours(7).Date);

                    foreach (var dayGroup in groupedByDate)
                    {
                        attendedDays++;
                        var checkIn = dayGroup.Where(a => a.AttendanceState == AttendanceStates.CheckIn)
                            .OrderBy(a => a.AttendanceTime).FirstOrDefault();
                        var checkOut = dayGroup.Where(a => a.AttendanceState == AttendanceStates.CheckOut)
                            .OrderByDescending(a => a.AttendanceTime).FirstOrDefault();

                        if (checkIn?.AttendanceTime.AddHours(7).TimeOfDay > lateThreshold)
                        {
                            lateCount++;
                        }

                        if (checkIn != null && checkOut != null)
                        {
                            totalWorkedMinutes += (int)(checkOut.AttendanceTime - checkIn.AttendanceTime).TotalMinutes;
                        }
                    }
                }

                var expectedAttendance = deptEmployees.Count * workingDays;
                var attendanceRate = expectedAttendance > 0 
                    ? Math.Round((double)attendedDays / expectedAttendance * 100, 2) 
                    : 0;

                reportItems.Add(new DepartmentSummaryItemDto
                {
                    DepartmentId = Guid.Empty, // No DepartmentId since it's a string field
                    DepartmentName = dept.Key,
                    EmployeeCount = deptEmployees.Count,
                    TotalAttendance = attendedDays,
                    TotalLateCount = lateCount,
                    TotalWorkedHours = Math.Round(totalWorkedMinutes / 60.0, 2),
                    AverageWorkedHoursPerDay = attendedDays > 0 
                        ? Math.Round(totalWorkedMinutes / 60.0 / attendedDays, 2) 
                        : 0,
                    AttendanceRate = attendanceRate
                });
            }

            var report = new DepartmentSummaryReportDto
            {
                Year = targetYear,
                Month = targetMonth,
                WorkingDays = workingDays,
                TotalDepartments = departments.Count,
                TotalEmployees = employees.Count,
                Items = reportItems.OrderByDescending(i => i.AttendanceRate).ToList()
            };

            return Ok(AppResponse<DepartmentSummaryReportDto>.Success(report));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error generating department summary report");
            return StatusCode(500, AppResponse<DepartmentSummaryReportDto>.Fail("Error generating report"));
        }
    }

    #endregion

    #region Overtime Report

    /// <summary>
    /// Get overtime report
    /// </summary>
    [HttpGet("overtime")]
    [RequireAnyModulePermission(ModulePermissionAction.View, "AttendanceReport", "AttendanceSummary", "AttendanceByShift", "Attendance")]
    public async Task<ActionResult<AppResponse<OvertimeReportDto>>> GetOvertimeReport(
        [FromQuery] DateTime? startDate = null,
        [FromQuery] DateTime? endDate = null,
        [FromQuery] string? department = null,
        [FromQuery] Guid? branchId = null,
        [FromQuery] bool includeChildBranches = true,
        [FromQuery] int? minOvertimeMinutes = 0)
    {
        try
        {
            var storeId = RequiredStoreId;
            var start = startDate ?? DateTime.Today.AddMonths(-1);
            var end = endDate ?? DateTime.Today;
            var minOvertime = minOvertimeMinutes ?? 0;

            var employeesQuery = dbContext.Employees
                .Where(e => e.StoreId == storeId && e.Deleted == null);

            employeesQuery = await FilterEmployeesQueryAsync(
                employeesQuery, storeId, department, branchId, includeChildBranches, employeeCodes: null);

            var employees = await employeesQuery.ToListAsync();

            var employeePins = employees.Select(e => e.EmployeeCode).ToList();

            var attendances = await dbContext.AttendanceLogs
                .Where(a => a.Device != null && a.Device.StoreId == storeId 
                    && a.AttendanceTime >= start 
                    && a.AttendanceTime <= end.AddDays(1)
                    && employeePins.Contains(a.PIN))
                .Select(a => new { a.PIN, a.AttendanceTime, a.AttendanceState })
                .ToListAsync();

            // Build attendance lookup by PIN for O(1) access
            var attendanceByPin = attendances.ToLookup(a => a.PIN);

            var reportItems = new List<OvertimeItemDto>();
            var totalOvertimeMinutes = 0;

            // Standard work hours: 9 hours (8:30 AM - 6:00 PM with 30 min break assumed)
            var standardWorkMinutes = 9 * 60;

            foreach (var employee in employees)
            {
                // O(1) lookup instead of scanning entire list
                var empAttendances = attendanceByPin[employee.EmployeeCode].ToList();
                var groupedByDate = empAttendances.GroupBy(a => a.AttendanceTime.Date);

                var overtimeMinutes = 0;
                var overtimeDays = 0;
                var overtimeDetails = new List<OvertimeDayDetailDto>();

                foreach (var dayGroup in groupedByDate)
                {
                    var checkIn = dayGroup.Where(a => a.AttendanceState == AttendanceStates.CheckIn)
                        .OrderBy(a => a.AttendanceTime).FirstOrDefault();
                    var checkOut = dayGroup.Where(a => a.AttendanceState == AttendanceStates.CheckOut)
                        .OrderByDescending(a => a.AttendanceTime).FirstOrDefault();

                    if (checkIn != null && checkOut != null)
                    {
                        var workedMinutes = ReportsExportHelpers.WorkedMinutesVn(
                            checkIn.AttendanceTime, checkOut.AttendanceTime);
                        if (workedMinutes > standardWorkMinutes)
                        {
                            var dayOvertime = workedMinutes - standardWorkMinutes;
                            overtimeMinutes += dayOvertime;
                            overtimeDays++;
                            
                            overtimeDetails.Add(new OvertimeDayDetailDto
                            {
                                Date = dayGroup.Key,
                                CheckInTime = checkIn.AttendanceTime,
                                CheckOutTime = checkOut.AttendanceTime,
                                WorkedMinutes = workedMinutes,
                                OvertimeMinutes = dayOvertime
                            });
                        }
                    }
                }

                if (overtimeMinutes >= minOvertime)
                {
                    reportItems.Add(new OvertimeItemDto
                    {
                        EmployeeId = employee.Id,
                        EmployeeCode = employee.EmployeeCode,
                        EmployeeName = $"{employee.LastName} {employee.FirstName}".Trim(),
                        DepartmentName = employee.Department ?? "N/A",
                        TotalOvertimeMinutes = overtimeMinutes,
                        TotalOvertimeHours = Math.Round(overtimeMinutes / 60.0, 2),
                        OvertimeDays = overtimeDays,
                        Details = overtimeDetails
                    });

                    totalOvertimeMinutes += overtimeMinutes;
                }
            }

            var report = new OvertimeReportDto
            {
                StartDate = start,
                EndDate = end,
                TotalEmployees = employees.Count,
                EmployeesWithOvertime = reportItems.Count,
                TotalOvertimeMinutes = totalOvertimeMinutes,
                TotalOvertimeHours = Math.Round(totalOvertimeMinutes / 60.0, 2),
                Items = reportItems.OrderByDescending(i => i.TotalOvertimeMinutes).ToList()
            };

            return Ok(AppResponse<OvertimeReportDto>.Success(report));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error generating overtime report");
            return StatusCode(500, AppResponse<OvertimeReportDto>.Fail("Error generating report"));
        }
    }

    #endregion

    #region Leave Summary Report

    /// <summary>
    /// Get leave summary report
    /// </summary>
    [HttpGet("leave-summary")]
    [RequireModulePermission("LeaveReport", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<LeaveSummaryReportDto>>> GetLeaveSummaryReport(
        [FromQuery] DateTime? startDate = null,
        [FromQuery] DateTime? endDate = null,
        [FromQuery] string? department = null,
        [FromQuery] Guid? branchId = null,
        [FromQuery] bool includeChildBranches = true)
    {
        try
        {
            var storeId = RequiredStoreId;
            var start = startDate ?? new DateTime(DateTime.Now.Year, 1, 1);
            var end = endDate ?? DateTime.Today;

            var employeesQuery = dbContext.Employees
                .Where(e => e.StoreId == storeId && e.Deleted == null);

            employeesQuery = await FilterEmployeesQueryAsync(
                employeesQuery, storeId, department, branchId, includeChildBranches, employeeCodes: null);

            var employees = await employeesQuery.ToListAsync();

            var employeeUserIds = employees
                .Where(e => e.ApplicationUserId.HasValue)
                .ToDictionary(e => e.ApplicationUserId!.Value, e => e);

            var leaves = await dbContext.Leaves
                .Where(l => l.StoreId == storeId
                    && l.StartDate <= end
                    && l.EndDate >= start
                    && employeeUserIds.Keys.Contains(l.EmployeeUserId))
                .ToListAsync();

            var leavesByUser = leaves.ToLookup(l => l.EmployeeUserId);

            var reportItems = new List<LeaveSummaryItemDto>();
            var totalLeaveRequests = 0;
            var totalLeaveDays = 0;
            var approvedCount = 0;
            var rejectedCount = 0;
            var pendingCount = 0;

            foreach (var kvp in employeeUserIds)
            {
                var userId = kvp.Key;
                var employee = kvp.Value;
                var empLeaves = leavesByUser[userId].ToList();
                
                if (empLeaves.Count == 0) continue;

                var approved = empLeaves.Where(l => l.Status == LeaveStatus.Approved).ToList();
                var rejected = empLeaves.Where(l => l.Status == LeaveStatus.Rejected).ToList();
                var pending = empLeaves.Where(l => l.Status == LeaveStatus.Pending).ToList();
                var activeLeaves = empLeaves
                    .Where(l => l.Status != LeaveStatus.Rejected && l.Status != LeaveStatus.Cancelled)
                    .ToList();

                var usedDays = 0;
                foreach (var leave in approved)
                {
                    var leaveStart = leave.StartDate < start ? start : leave.StartDate;
                    var leaveEnd = leave.EndDate > end ? end : leave.EndDate;
                    usedDays += (int)(leaveEnd - leaveStart).TotalDays + 1;
                }

                totalLeaveRequests += activeLeaves.Count;
                totalLeaveDays += usedDays;
                approvedCount += approved.Count;
                rejectedCount += rejected.Count;
                pendingCount += pending.Count;

                // Determine most common leave type
                var leaveType = approved.Any()
                    ? approved.GroupBy(l => l.Type.ToString())
                        .OrderByDescending(g => g.Count())
                        .First().Key
                    : empLeaves.First().Type.ToString();

                reportItems.Add(new LeaveSummaryItemDto
                {
                    EmployeeId = employee.Id,
                    EmployeeCode = employee.EmployeeCode,
                    EmployeeName = $"{employee.LastName} {employee.FirstName}".Trim(),
                    DepartmentName = employee.Department ?? "N/A",
                    LeaveType = leaveType,
                    TotalRequests = activeLeaves.Count,
                    TotalDays = usedDays,
                    UsedDays = usedDays,
                    RemainingDays = 12 - usedDays, // Assuming 12 days/year default
                    ApprovedCount = approved.Count,
                    RejectedCount = rejected.Count,
                    PendingCount = pending.Count
                });
            }

            var report = new LeaveSummaryReportDto
            {
                StartDate = start,
                EndDate = end,
                TotalEmployees = employees.Count,
                EmployeesWithLeave = reportItems.Count,
                TotalLeaveRequests = totalLeaveRequests,
                TotalLeaveDays = totalLeaveDays,
                ApprovedCount = approvedCount,
                RejectedCount = rejectedCount,
                PendingCount = pendingCount,
                Items = reportItems.OrderByDescending(i => i.TotalDays).ToList()
            };

            return Ok(AppResponse<LeaveSummaryReportDto>.Success(report));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error generating leave summary report");
            return StatusCode(500, AppResponse<LeaveSummaryReportDto>.Fail("Error generating report"));
        }
    }

    #endregion

    #region Export Endpoints

    /// <summary>
    /// Export daily attendance report to CSV
    /// </summary>
    [HttpGet("export/daily")]
    [RequireAnyModulePermission(ModulePermissionAction.Export, "AttendanceReport", "AttendanceSummary", "AttendanceByShift", "Attendance")]
    public async Task<IActionResult> ExportDailyReport(
        [FromQuery] DateTime? date = null,
        [FromQuery] string format = "csv",
        [FromQuery] string? department = null,
        [FromQuery] string? employeeCodes = null,
        [FromQuery] Guid? branchId = null,
        [FromQuery] bool includeChildBranches = true)
    {
        var reportResult = await GetDailyAttendanceReport(
            date, department, null, employeeCodes, branchId, includeChildBranches);
        if (reportResult.Result is not OkObjectResult okResult 
            || okResult.Value is not AppResponse<DailyAttendanceReportDto> response 
            || response.Data == null)
        {
            return BadRequest("Failed to generate report");
        }

        var report = response.Data;

        if (format.ToLower() == "json")
        {
            return Ok(report);
        }

        var csv = new StringBuilder();
        csv.AppendLine("STT,Mã NV,Họ tên,Phòng ban,Giờ vào,Giờ ra,Đi muộn (phút),Về sớm (phút),Thời gian làm (phút),Trạng thái,Ghi chú");
        
        var stt = 1;
        foreach (var item in report.Items)
        {
            csv.AppendLine(string.Join(",",
                stt++.ToString(),
                ReportsExportHelpers.CsvEscape(item.EmployeeCode),
                ReportsExportHelpers.CsvEscape(item.EmployeeName),
                ReportsExportHelpers.CsvEscape(item.DepartmentName),
                ReportsExportHelpers.CsvEscape(ReportsExportHelpers.FormatVnTime(item.CheckInTime)),
                ReportsExportHelpers.CsvEscape(ReportsExportHelpers.FormatVnTime(item.CheckOutTime)),
                item.LateMinutes.ToString(),
                item.EarlyLeaveMinutes.ToString(),
                item.WorkedMinutes.ToString(),
                ReportsExportHelpers.CsvEscape(item.Status),
                ReportsExportHelpers.CsvEscape(item.Note ?? "")));
        }

        var bytes = Encoding.UTF8.GetPreamble().Concat(Encoding.UTF8.GetBytes(csv.ToString())).ToArray();
        return File(bytes, "text/csv; charset=utf-8", $"bao_cao_cham_cong_{report.Date:yyyyMMdd}.csv");
    }

    /// <summary>
    /// Export monthly attendance report to CSV
    /// </summary>
    [HttpGet("export/monthly")]
    [RequireAnyModulePermission(ModulePermissionAction.Export, "AttendanceReport", "AttendanceSummary", "AttendanceByShift", "Attendance")]
    public async Task<IActionResult> ExportMonthlyReport(
        [FromQuery] int? year = null,
        [FromQuery] int? month = null,
        [FromQuery] string format = "csv",
        [FromQuery] string? department = null,
        [FromQuery] string? employeeCodes = null,
        [FromQuery] Guid? branchId = null,
        [FromQuery] bool includeChildBranches = true)
    {
        var reportResult = await GetMonthlyAttendanceReport(
            year, month, department, employeeCodes, branchId, includeChildBranches);
        if (reportResult.Result is not OkObjectResult okResult 
            || okResult.Value is not AppResponse<MonthlyAttendanceReportDto> response 
            || response.Data == null)
        {
            return BadRequest("Failed to generate report");
        }

        var report = response.Data;

        if (format.ToLower() == "json")
        {
            return Ok(report);
        }

        var csv = new StringBuilder();
        csv.AppendLine("STT,Mã NV,Họ tên,Phòng ban,Ngày làm,Ngày muộn,Ngày nghỉ,Ngày vắng,Số giờ làm,Tỷ lệ CC (%),Ghi chú");
        
        var stt = 1;
        foreach (var item in report.Items)
        {
            csv.AppendLine(string.Join(",",
                stt++.ToString(),
                ReportsExportHelpers.CsvEscape(item.EmployeeCode),
                ReportsExportHelpers.CsvEscape(item.EmployeeName),
                ReportsExportHelpers.CsvEscape(item.DepartmentName),
                item.TotalDaysWorked.ToString(),
                item.TotalLateDays.ToString(),
                item.TotalLeaveDays.ToString(),
                item.TotalAbsentDays.ToString(),
                item.TotalWorkedHours.ToString(),
                item.AttendanceRate.ToString(),
                ReportsExportHelpers.CsvEscape(item.Note ?? "")));
        }

        var bytes = Encoding.UTF8.GetPreamble().Concat(Encoding.UTF8.GetBytes(csv.ToString())).ToArray();
        return File(bytes, "text/csv; charset=utf-8", $"bao_cao_thang_{report.Year}_{report.Month:D2}.csv");
    }

    /// <summary>
    /// Export late/early report to CSV
    /// </summary>
    [HttpGet("export/late-early")]
    [RequireAnyModulePermission(ModulePermissionAction.Export, "AttendanceReport", "AttendanceSummary", "AttendanceByShift", "Attendance")]
    public async Task<IActionResult> ExportLateEarlyReport(
        [FromQuery] DateTime? startDate = null,
        [FromQuery] DateTime? endDate = null,
        [FromQuery] string format = "csv",
        [FromQuery] string? department = null,
        [FromQuery] string? employeeCodes = null,
        [FromQuery] Guid? branchId = null,
        [FromQuery] bool includeChildBranches = true)
    {
        var reportResult = await GetLateEarlyReport(
            startDate, endDate, department, employeeCodes, branchId, includeChildBranches);
        if (reportResult.Result is not OkObjectResult okResult 
            || okResult.Value is not AppResponse<LateEarlyReportDto> response 
            || response.Data == null)
        {
            return BadRequest("Failed to generate report");
        }

        var report = response.Data;

        if (format.ToLower() == "json")
        {
            return Ok(report);
        }

        var csv = new StringBuilder();
        csv.AppendLine("STT,Mã NV,Họ tên,Phòng ban,Số lần muộn,Tổng phút muộn,Số lần về sớm,Tổng phút về sớm");
        
        var stt = 1;
        foreach (var item in report.Items)
        {
            csv.AppendLine($"{stt++},\"{item.EmployeeCode}\",\"{item.EmployeeName}\",\"{item.DepartmentName}\",{item.LateCount},{item.TotalLateMinutes},{item.EarlyLeaveCount},{item.TotalEarlyMinutes}");
        }

        var bytes = Encoding.UTF8.GetPreamble().Concat(Encoding.UTF8.GetBytes(csv.ToString())).ToArray();
        return File(bytes, "text/csv; charset=utf-8", $"bao_cao_di_muon_{report.StartDate:yyyyMMdd}_{report.EndDate:yyyyMMdd}.csv");
    }

    #endregion

    #region Excel Export Endpoints

    /// <summary>
    /// Export daily attendance report to Excel
    /// </summary>
    [HttpGet("export/excel/daily")]
    [RequireAnyModulePermission(ModulePermissionAction.Export, "AttendanceReport", "AttendanceSummary", "AttendanceByShift", "Attendance")]
    public async Task<IActionResult> ExportDailyReportExcel(
        [FromQuery] DateTime? date = null,
        [FromQuery] string? department = null,
        [FromQuery] string? employeeCodes = null,
        [FromQuery] Guid? branchId = null,
        [FromQuery] bool includeChildBranches = true)
    {
        try
        {
            var reportResult = await GetDailyAttendanceReport(
                date, department, null, employeeCodes, branchId, includeChildBranches);
            if (reportResult.Result is not OkObjectResult okResult 
                || okResult.Value is not AppResponse<DailyAttendanceReportDto> response 
                || response.Data == null)
            {
                return BadRequest("Failed to generate report");
            }

            var report = response.Data;

            using var workbook = new XLWorkbook();
            var worksheet = workbook.Worksheets.Add("Báo cáo chấm công");

            var headers = new[] { "STT", "Mã NV", "Họ tên", "Phòng ban", "Giờ vào", "Giờ ra", "Muộn (phút)", "Về sớm (phút)", "Làm (phút)", "Trạng thái", "Ghi chú" };
            var filterLabel = BuildAttendanceExportFilter(department, employeeCodes, branchId);
            var summary = new[]
            {
                $"Tổng số NV: {report.TotalEmployees} | Có mặt: {report.Present} | Đi muộn: {report.Late} | Về sớm: {report.EarlyLeave} | Vắng: {report.Absent}"
            };
            var (headerRow, dataStartRow) = WriteAttendanceExcelMeta(
                worksheet, "BÁO CÁO CHẤM CÔNG NGÀY", headers.Length,
                $"Ngày {report.Date:dd/MM/yyyy}", filterLabel, summary, report.Items.Count);
            ReportExcelLayout.ApplyHeaderRow(worksheet, headerRow, headers);

            var row = dataStartRow;
            var stt = 1;
            foreach (var item in report.Items)
            {
                worksheet.Cell(row, 1).Value = stt++;
                worksheet.Cell(row, 2).Value = item.EmployeeCode;
                worksheet.Cell(row, 3).Value = item.EmployeeName;
                worksheet.Cell(row, 4).Value = item.DepartmentName;
                worksheet.Cell(row, 5).Value = ReportsExportHelpers.FormatVnTime(item.CheckInTime);
                worksheet.Cell(row, 6).Value = ReportsExportHelpers.FormatVnTime(item.CheckOutTime);
                worksheet.Cell(row, 7).Value = item.LateMinutes;
                worksheet.Cell(row, 8).Value = item.EarlyLeaveMinutes;
                worksheet.Cell(row, 9).Value = item.WorkedMinutes;
                worksheet.Cell(row, 10).Value = item.Status;
                worksheet.Cell(row, 11).Value = item.Note ?? "";

                ReportsExportHelpers.ApplyDailyStatusFill(worksheet.Cell(row, 10), item.Status);
                row++;
            }

            ReportExcelLayout.FinishSheet(worksheet, headerRow);

            using var stream = new MemoryStream();
            workbook.SaveAs(stream);
            var content = stream.ToArray();

            return File(content, 
                "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", 
                $"bao_cao_cham_cong_{report.Date:yyyyMMdd}.xlsx");
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error exporting daily report to Excel");
            return BadRequest($"Export failed: {ex.Message}");
        }
    }

    /// <summary>
    /// Export monthly attendance report to Excel
    /// </summary>
    [HttpGet("export/excel/monthly")]
    [RequireAnyModulePermission(ModulePermissionAction.Export, "AttendanceReport", "AttendanceSummary", "AttendanceByShift", "Attendance")]
    public async Task<IActionResult> ExportMonthlyReportExcel(
        [FromQuery] int? year = null,
        [FromQuery] int? month = null,
        [FromQuery] string? department = null,
        [FromQuery] string? employeeCodes = null,
        [FromQuery] Guid? branchId = null,
        [FromQuery] bool includeChildBranches = true)
    {
        try
        {
            var reportResult = await GetMonthlyAttendanceReport(
                year, month, department, employeeCodes, branchId, includeChildBranches);
            if (reportResult.Result is not OkObjectResult okResult 
                || okResult.Value is not AppResponse<MonthlyAttendanceReportDto> response 
                || response.Data == null)
            {
                return BadRequest("Failed to generate report");
            }

            var report = response.Data;

            using var workbook = new XLWorkbook();
            var worksheet = workbook.Worksheets.Add("Báo cáo tháng");

            var headers = new[] { "STT", "Mã NV", "Họ tên", "Phòng ban", "Ngày làm", "Ngày muộn", "Ngày nghỉ", "Ngày vắng", "Giờ làm", "Tỷ lệ (%)", "Ghi chú" };
            var filterLabel = BuildAttendanceExportFilter(department, employeeCodes, branchId);
            var summary = new List<string>
            {
                $"Số ngày làm việc: {report.WorkingDays} | Tổng NV: {report.TotalEmployees}"
            };
            if (report.NoSalaryProfile > 0)
                summary.Add($"Cảnh báo: {report.NoSalaryProfile} nhân viên chưa thiết lập hồ sơ lương — xem cột Ghi chú.");
            var (headerRow, dataStartRow) = WriteAttendanceExcelMeta(
                worksheet, "BÁO CÁO CHẤM CÔNG THÁNG", headers.Length,
                $"Tháng {report.Month}/{report.Year}", filterLabel, summary, report.Items.Count);
            ReportExcelLayout.ApplyHeaderRow(worksheet, headerRow, headers);

            var row = dataStartRow;
            var stt = 1;
            foreach (var item in report.Items)
            {
                worksheet.Cell(row, 1).Value = stt++;
                worksheet.Cell(row, 2).Value = item.EmployeeCode;
                worksheet.Cell(row, 3).Value = item.EmployeeName;
                worksheet.Cell(row, 4).Value = item.DepartmentName;
                worksheet.Cell(row, 5).Value = item.TotalDaysWorked;
                worksheet.Cell(row, 6).Value = item.TotalLateDays;
                worksheet.Cell(row, 7).Value = item.TotalLeaveDays;
                worksheet.Cell(row, 8).Value = item.TotalAbsentDays;
                worksheet.Cell(row, 9).Value = Math.Round(item.TotalWorkedHours, 1);
                worksheet.Cell(row, 10).Value = Math.Round(item.AttendanceRate, 1);
                worksheet.Cell(row, 11).Value = item.Note ?? "";

                if (!item.HasSalaryProfile)
                {
                    worksheet.Range(row, 1, row, headers.Length).Style
                        .Fill.SetBackgroundColor(XLColor.LightYellow);
                }

                // Color for attendance rate
                var rateCell = worksheet.Cell(row, 10);
                if (item.AttendanceRate >= 95)
                    rateCell.Style.Fill.SetBackgroundColor(XLColor.LightGreen);
                else if (item.AttendanceRate >= 80)
                    rateCell.Style.Fill.SetBackgroundColor(XLColor.LightYellow);
                else
                    rateCell.Style.Fill.SetBackgroundColor(XLColor.LightPink);

                row++;
            }

            ReportExcelLayout.FinishSheet(worksheet, headerRow);

            using var stream = new MemoryStream();
            workbook.SaveAs(stream);
            var content = stream.ToArray();

            return File(content, 
                "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", 
                $"bao_cao_thang_{report.Year}_{report.Month:D2}.xlsx");
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error exporting monthly report to Excel");
            return BadRequest($"Export failed: {ex.Message}");
        }
    }

    /// <summary>
    /// Export employee attendance report to Excel
    /// </summary>
    [HttpGet("export/excel/employee/{employeeId}")]
    [RequireAnyModulePermission(ModulePermissionAction.Export, "AttendanceReport", "AttendanceSummary", "AttendanceByShift", "Attendance")]
    public async Task<IActionResult> ExportEmployeeReportExcel(
        Guid employeeId,
        [FromQuery] DateTime? startDate = null,
        [FromQuery] DateTime? endDate = null)
    {
        try
        {
            var reportResult = await GetEmployeeAttendanceReport(employeeId, startDate, endDate);
            if (reportResult.Result is not OkObjectResult okResult 
                || okResult.Value is not AppResponse<EmployeeAttendanceReportDto> response 
                || response.Data == null)
            {
                return BadRequest("Failed to generate report");
            }

            var report = response.Data;

            using var workbook = new XLWorkbook();
            var worksheet = workbook.Worksheets.Add("Báo cáo cá nhân");

            var headers = new[] { "Ngày", "Thứ", "Giờ vào", "Giờ ra", "Giờ làm (phút)", "Muộn", "Về sớm", "Trạng thái" };
            var summary = new[]
            {
                $"Mã NV: {report.EmployeeCode} | Họ tên: {report.EmployeeName} | Phòng ban: {report.DepartmentName} | Chức vụ: {report.Position}",
                $"Ngày có mặt: {report.TotalPresentDays} | Đi muộn: {report.TotalLateDays} | Về sớm: {report.TotalEarlyLeaveDays} | Nghỉ phép: {report.TotalLeaveDays} | Vắng: {report.TotalAbsentDays}",
                $"Tổng giờ làm: {report.TotalWorkedHours:F1}h | Tỷ lệ chấm công: {report.AttendanceRate:F1}%"
            };
            var (headerRow, dataStartRow) = WriteAttendanceExcelMeta(
                worksheet, "BÁO CÁO CHẤM CÔNG CÁ NHÂN", headers.Length,
                $"{report.StartDate:dd/MM/yyyy} – {report.EndDate:dd/MM/yyyy}", null, summary, report.DailyRecords.Count);
            ReportExcelLayout.ApplyHeaderRow(worksheet, headerRow, headers);

            var row = dataStartRow;
            foreach (var item in report.DailyRecords)
            {
                worksheet.Cell(row, 1).Value = item.Date.ToString("dd/MM");
                worksheet.Cell(row, 2).Value = item.DayOfWeek;
                worksheet.Cell(row, 3).Value = ReportsExportHelpers.FormatVnTime(item.CheckInTime);
                worksheet.Cell(row, 4).Value = ReportsExportHelpers.FormatVnTime(item.CheckOutTime);
                worksheet.Cell(row, 5).Value = item.WorkedMinutes;
                worksheet.Cell(row, 6).Value = item.IsLate ? "✓" : "";
                worksheet.Cell(row, 7).Value = item.IsEarlyLeave ? "✓" : "";
                worksheet.Cell(row, 8).Value = item.Status;

                // Color coding
                if (item.IsHoliday || item.Date.DayOfWeek == DayOfWeek.Saturday || item.Date.DayOfWeek == DayOfWeek.Sunday)
                {
                    worksheet.Range(row, 1, row, 8).Style.Fill.SetBackgroundColor(XLColor.LightGray);
                }
                else if (item.Status == ReportLabels.Absent)
                {
                    worksheet.Range(row, 1, row, 8).Style.Fill.SetBackgroundColor(XLColor.LightPink);
                }
                else if (item.IsOnLeave)
                {
                    worksheet.Range(row, 1, row, 8).Style.Fill.SetBackgroundColor(XLColor.LightYellow);
                }
                else
                {
                    ReportsExportHelpers.ApplyDailyStatusFill(worksheet.Cell(row, 8), item.Status);
                }

                row++;
            }

            ReportExcelLayout.FinishSheet(worksheet, headerRow);

            using var stream = new MemoryStream();
            workbook.SaveAs(stream);
            var content = stream.ToArray();

            return File(content, 
                "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", 
                $"bao_cao_{report.EmployeeCode}_{report.StartDate:yyyyMMdd}_{report.EndDate:yyyyMMdd}.xlsx");
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error exporting employee report to Excel");
            return BadRequest($"Export failed: {ex.Message}");
        }
    }

    /// <summary>
    /// Export late/early report to Excel
    /// </summary>
    [HttpGet("export/excel/late-early")]
    [RequireAnyModulePermission(ModulePermissionAction.Export, "AttendanceReport", "AttendanceSummary", "AttendanceByShift", "Attendance")]
    public async Task<IActionResult> ExportLateEarlyReportExcel(
        [FromQuery] DateTime? startDate = null,
        [FromQuery] DateTime? endDate = null,
        [FromQuery] string? department = null,
        [FromQuery] string? employeeCodes = null,
        [FromQuery] Guid? branchId = null,
        [FromQuery] bool includeChildBranches = true)
    {
        try
        {
            var reportResult = await GetLateEarlyReport(
                startDate, endDate, department, employeeCodes, branchId, includeChildBranches);
            if (reportResult.Result is not OkObjectResult okResult 
                || okResult.Value is not AppResponse<LateEarlyReportDto> response 
                || response.Data == null)
            {
                return BadRequest("Failed to generate report");
            }

            var report = response.Data;

            using var workbook = new XLWorkbook();
            var worksheet = workbook.Worksheets.Add("Báo cáo đi muộn về sớm");

            var headers = new[] { "STT", "Mã NV", "Họ tên", "Phòng ban", "Lần muộn", "Phút muộn", "Lần về sớm", "Phút về sớm" };
            var filterLabel = BuildAttendanceExportFilter(department, employeeCodes, branchId);
            var summary = new[]
            {
                $"Tổng NV: {report.TotalEmployees} | Vi phạm: {report.EmployeesWithIssues} | Lần muộn: {report.TotalLateCount} ({report.TotalLateMinutes} phút) | Về sớm: {report.TotalEarlyLeaveCount} ({report.TotalEarlyMinutes} phút)"
            };
            var (headerRow, dataStartRow) = WriteAttendanceExcelMeta(
                worksheet, "BÁO CÁO ĐI MUỘN - VỀ SỚM", headers.Length,
                $"{report.StartDate:dd/MM/yyyy} – {report.EndDate:dd/MM/yyyy}", filterLabel, summary, report.Items.Count);
            ReportExcelLayout.ApplyHeaderRow(worksheet, headerRow, headers);

            var row = dataStartRow;
            var stt = 1;
            foreach (var item in report.Items)
            {
                worksheet.Cell(row, 1).Value = stt++;
                worksheet.Cell(row, 2).Value = item.EmployeeCode;
                worksheet.Cell(row, 3).Value = item.EmployeeName;
                worksheet.Cell(row, 4).Value = item.DepartmentName;
                worksheet.Cell(row, 5).Value = item.LateCount;
                worksheet.Cell(row, 6).Value = item.TotalLateMinutes;
                worksheet.Cell(row, 7).Value = item.EarlyLeaveCount;
                worksheet.Cell(row, 8).Value = item.TotalEarlyMinutes;

                // Highlight high violations
                if (item.LateCount >= 5 || item.EarlyLeaveCount >= 5)
                {
                    worksheet.Range(row, 1, row, 8).Style.Fill.SetBackgroundColor(XLColor.LightPink);
                }

                row++;
            }

            // Auto-fit columns
            ReportExcelLayout.FinishSheet(worksheet, headerRow);

            using var stream = new MemoryStream();
            workbook.SaveAs(stream);
            var content = stream.ToArray();

            return File(content, 
                "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", 
                $"bao_cao_di_muon_{report.StartDate:yyyyMMdd}_{report.EndDate:yyyyMMdd}.xlsx");
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error exporting late/early report to Excel");
            return BadRequest($"Export failed: {ex.Message}");
        }
    }

    /// <summary>
    /// Export department summary report to Excel
    /// </summary>
    [HttpGet("export/excel/department")]
    [RequireAnyModulePermission(ModulePermissionAction.Export, "AttendanceReport", "AttendanceSummary", "AttendanceByShift", "Attendance")]
    public async Task<IActionResult> ExportDepartmentSummaryExcel(
        [FromQuery] int? year = null,
        [FromQuery] int? month = null)
    {
        try
        {
            var reportResult = await GetDepartmentSummaryReport(year, month);
            if (reportResult.Result is not OkObjectResult okResult 
                || okResult.Value is not AppResponse<DepartmentSummaryReportDto> response 
                || response.Data == null)
            {
                return BadRequest("Failed to generate report");
            }

            var report = response.Data;

            using var workbook = new XLWorkbook();
            var worksheet = workbook.Worksheets.Add("Báo cáo theo phòng ban");

            var headers = new[] { "STT", "Phòng ban", "Số NV", "Tổng chấm công", "Số lần muộn", "Tổng giờ làm", "Tỷ lệ CC (%)" };
            var (headerRow, dataStartRow) = WriteAttendanceExcelMeta(
                worksheet, "BÁO CÁO TỔNG HỢP THEO PHÒNG BAN", headers.Length,
                $"Tháng {report.Month}/{report.Year}", null, null, report.Items.Count);
            ReportExcelLayout.ApplyHeaderRow(worksheet, headerRow, headers);

            var row = dataStartRow;
            var stt = 1;
            foreach (var item in report.Items)
            {
                worksheet.Cell(row, 1).Value = stt++;
                worksheet.Cell(row, 2).Value = item.DepartmentName;
                worksheet.Cell(row, 3).Value = item.EmployeeCount;
                worksheet.Cell(row, 4).Value = item.TotalAttendance;
                worksheet.Cell(row, 5).Value = item.TotalLateCount;
                worksheet.Cell(row, 6).Value = Math.Round(item.TotalWorkedHours, 1);
                worksheet.Cell(row, 7).Value = Math.Round(item.AttendanceRate, 1);

                row++;
            }

            // Auto-fit columns
            ReportExcelLayout.FinishSheet(worksheet, headerRow);

            using var stream = new MemoryStream();
            workbook.SaveAs(stream);
            var content = stream.ToArray();

            return File(content, 
                "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", 
                $"bao_cao_phong_ban_{report.Year}_{report.Month:D2}.xlsx");
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error exporting department summary to Excel");
            return BadRequest($"Export failed: {ex.Message}");
        }
    }

    /// <summary>
    /// Export overtime report to Excel
    /// </summary>
    [HttpGet("export/excel/overtime")]
    [RequireAnyModulePermission(ModulePermissionAction.Export, "AttendanceReport", "AttendanceSummary", "AttendanceByShift", "Attendance")]
    public async Task<IActionResult> ExportOvertimeReportExcel(
        [FromQuery] DateTime? startDate = null,
        [FromQuery] DateTime? endDate = null)
    {
        try
        {
            var reportResult = await GetOvertimeReport(startDate, endDate);
            if (reportResult.Result is not OkObjectResult okResult 
                || okResult.Value is not AppResponse<OvertimeReportDto> response 
                || response.Data == null)
            {
                return BadRequest("Failed to generate report");
            }

            var report = response.Data;

            using var workbook = new XLWorkbook();
            var worksheet = workbook.Worksheets.Add("Báo cáo tăng ca");

            var headers = new[] { "STT", "Mã NV", "Họ tên", "Phòng ban", "Số ngày tăng ca", "Tổng phút tăng ca", "Tổng giờ tăng ca" };
            var summary = new[]
            {
                $"Tổng NV: {report.TotalEmployees} | NV tăng ca: {report.EmployeesWithOvertime} | Tổng giờ: {report.TotalOvertimeHours:F1}h"
            };
            var (headerRow, dataStartRow) = WriteAttendanceExcelMeta(
                worksheet, "BÁO CÁO TĂNG CA", headers.Length,
                $"{report.StartDate:dd/MM/yyyy} – {report.EndDate:dd/MM/yyyy}", null, summary, report.Items.Count);
            ReportExcelLayout.ApplyHeaderRow(worksheet, headerRow, headers);

            var row = dataStartRow;
            var stt = 1;
            foreach (var item in report.Items)
            {
                worksheet.Cell(row, 1).Value = stt++;
                worksheet.Cell(row, 2).Value = item.EmployeeCode;
                worksheet.Cell(row, 3).Value = item.EmployeeName;
                worksheet.Cell(row, 4).Value = item.DepartmentName;
                worksheet.Cell(row, 5).Value = item.OvertimeDays;
                worksheet.Cell(row, 6).Value = item.TotalOvertimeMinutes;
                worksheet.Cell(row, 7).Value = Math.Round(item.TotalOvertimeHours, 1);

                if (item.TotalOvertimeHours >= 20)
                {
                    worksheet.Range(row, 1, row, 7).Style.Fill.SetBackgroundColor(XLColor.LightPink);
                }
                row++;
            }

            ReportExcelLayout.FinishSheet(worksheet, headerRow);

            using var stream = new MemoryStream();
            workbook.SaveAs(stream);
            var content = stream.ToArray();

            return File(content, 
                "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", 
                $"bao_cao_tang_ca_{report.StartDate:yyyyMMdd}_{report.EndDate:yyyyMMdd}.xlsx");
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error exporting overtime report to Excel");
            return BadRequest($"Export failed: {ex.Message}");
        }
    }

    /// <summary>
    /// Export leave summary report to Excel
    /// </summary>
    [HttpGet("export/excel/leave-summary")]
    [RequireModulePermission("LeaveReport", ModulePermissionAction.Export)]
    public async Task<IActionResult> ExportLeaveSummaryReportExcel(
        [FromQuery] DateTime? startDate = null,
        [FromQuery] DateTime? endDate = null)
    {
        try
        {
            var reportResult = await GetLeaveSummaryReport(startDate, endDate);
            if (reportResult.Result is not OkObjectResult okResult 
                || okResult.Value is not AppResponse<LeaveSummaryReportDto> response 
                || response.Data == null)
            {
                return BadRequest("Failed to generate report");
            }

            var report = response.Data;

            using var workbook = new XLWorkbook();
            var worksheet = workbook.Worksheets.Add("Báo cáo nghỉ phép");

            var headers = new[] { "STT", "Mã NV", "Họ tên", "Phòng ban", "Loại nghỉ", "Tổng đơn", "Ngày nghỉ", "Đã dùng", "Còn lại" };
            var summary = new[]
            {
                $"Tổng NV: {report.TotalEmployees} | NV nghỉ: {report.EmployeesWithLeave} | Tổng đơn: {report.TotalLeaveRequests} | Đã duyệt: {report.ApprovedCount} | Từ chối: {report.RejectedCount}"
            };
            var (headerRow, dataStartRow) = WriteAttendanceExcelMeta(
                worksheet, "BÁO CÁO NGHỈ PHÉP", headers.Length,
                $"{report.StartDate:dd/MM/yyyy} – {report.EndDate:dd/MM/yyyy}", null, summary, report.Items.Count);
            ReportExcelLayout.ApplyHeaderRow(worksheet, headerRow, headers);

            var row = dataStartRow;
            var stt = 1;
            foreach (var item in report.Items)
            {
                worksheet.Cell(row, 1).Value = stt++;
                worksheet.Cell(row, 2).Value = item.EmployeeCode;
                worksheet.Cell(row, 3).Value = item.EmployeeName;
                worksheet.Cell(row, 4).Value = item.DepartmentName;
                worksheet.Cell(row, 5).Value = item.LeaveType;
                worksheet.Cell(row, 6).Value = item.TotalRequests;
                worksheet.Cell(row, 7).Value = item.TotalDays;
                worksheet.Cell(row, 8).Value = item.UsedDays;
                worksheet.Cell(row, 9).Value = item.RemainingDays;

                if (item.RemainingDays <= 0)
                {
                    worksheet.Range(row, 1, row, 9).Style.Fill.SetBackgroundColor(XLColor.LightPink);
                }
                row++;
            }

            ReportExcelLayout.FinishSheet(worksheet, headerRow);

            using var stream = new MemoryStream();
            workbook.SaveAs(stream);
            var content = stream.ToArray();

            return File(content, 
                "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", 
                $"bao_cao_nghi_phep_{report.StartDate:yyyyMMdd}_{report.EndDate:yyyyMMdd}.xlsx");
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error exporting leave summary to Excel");
            return BadRequest($"Export failed: {ex.Message}");
        }
    }

    #endregion

    #region Helper Methods

    private string? BuildAttendanceExportFilter(string? department, string? employeeCodes, Guid? branchId)
    {
        var parts = new List<string>();
        if (!string.IsNullOrWhiteSpace(department)) parts.Add($"Phòng ban: {department}");
        if (!string.IsNullOrWhiteSpace(employeeCodes)) parts.Add($"Mã NV: {employeeCodes}");
        if (branchId.HasValue) parts.Add($"Chi nhánh: {branchId}");
        return parts.Count == 0 ? null : string.Join(" | ", parts);
    }

    private (int headerRow, int dataStartRow) WriteAttendanceExcelMeta(
        IXLWorksheet ws,
        string title,
        int columnCount,
        string? periodLabel = null,
        string? filterLabel = null,
        IReadOnlyList<string>? summaryLines = null,
        int? dataRowCount = null)
    {
        var meta = ReportExcelMeta.FromUser(User, title, periodLabel, filterLabel, summaryLines, dataRowCount);
        return ReportExcelLayout.ApplyMeta(ws, meta, columnCount);
    }

    private static string GetDayOfWeekVN(DayOfWeek day) => day switch
    {
        DayOfWeek.Monday => "Thứ 2",
        DayOfWeek.Tuesday => "Thứ 3",
        DayOfWeek.Wednesday => "Thứ 4",
        DayOfWeek.Thursday => "Thứ 5",
        DayOfWeek.Friday => "Thứ 6",
        DayOfWeek.Saturday => "Thứ 7",
        DayOfWeek.Sunday => "CN",
        _ => day.ToString()
    };

    #endregion
}

#region DTOs

// Daily Attendance Report DTOs
public class DailyAttendanceReportDto
{
    public DateTime Date { get; set; }
    public int TotalEmployees { get; set; }
    public int Present { get; set; }
    public int OnTime { get; set; }
    public int Late { get; set; }
    public int EarlyLeave { get; set; }
    public int Absent { get; set; }
    public int OnLeave { get; set; }
    public int NoSalaryProfile { get; set; }
    public double AttendanceRate { get; set; }
    public List<DailyAttendanceItemDto> Items { get; set; } = new();
}

public class DailyAttendanceItemDto
{
    public Guid EmployeeId { get; set; }
    public string EmployeeCode { get; set; } = string.Empty;
    public string EmployeeName { get; set; } = string.Empty;
    public string DepartmentName { get; set; } = string.Empty;
    public DateTime? CheckInTime { get; set; }
    public DateTime? CheckOutTime { get; set; }
    public int LateMinutes { get; set; }
    public int EarlyLeaveMinutes { get; set; }
    public int WorkedMinutes { get; set; }
    public string Status { get; set; } = string.Empty;
    public string? Note { get; set; }
}

// Monthly Attendance Report DTOs
public class MonthlyAttendanceReportDto
{
    public int Year { get; set; }
    public int Month { get; set; }
    public int WorkingDays { get; set; }
    public int TotalEmployees { get; set; }
    public int NoSalaryProfile { get; set; }
    public List<MonthlyAttendanceItemDto> Items { get; set; } = new();
}

public class MonthlyAttendanceItemDto
{
    public Guid EmployeeId { get; set; }
    public string EmployeeCode { get; set; } = string.Empty;
    public string EmployeeName { get; set; } = string.Empty;
    public string DepartmentName { get; set; } = string.Empty;
    public bool HasSalaryProfile { get; set; } = true;
    public string? Note { get; set; }
    public int TotalDaysWorked { get; set; }
    public int TotalLateDays { get; set; }
    public int TotalLeaveDays { get; set; }
    public int TotalAbsentDays { get; set; }
    public double TotalWorkedHours { get; set; }
    public double AttendanceRate { get; set; }
}

// Employee Attendance Report DTOs
public class EmployeeAttendanceReportDto
{
    public Guid EmployeeId { get; set; }
    public string EmployeeCode { get; set; } = string.Empty;
    public string EmployeeName { get; set; } = string.Empty;
    public string DepartmentName { get; set; } = string.Empty;
    public string Position { get; set; } = string.Empty;
    public DateTime StartDate { get; set; }
    public DateTime EndDate { get; set; }
    public int TotalWorkingDays { get; set; }
    public int TotalPresentDays { get; set; }
    public int TotalAbsentDays { get; set; }
    public int TotalLeaveDays { get; set; }
    public int TotalLateDays { get; set; }
    public int TotalEarlyLeaveDays { get; set; }
    public double TotalWorkedHours { get; set; }
    public double AttendanceRate { get; set; }
    public List<EmployeeAttendanceDayDto> DailyRecords { get; set; } = new();
}

public class EmployeeAttendanceDayDto
{
    public DateTime Date { get; set; }
    public string DayOfWeek { get; set; } = string.Empty;
    public DateTime? CheckInTime { get; set; }
    public DateTime? CheckOutTime { get; set; }
    public int WorkedMinutes { get; set; }
    public bool IsLate { get; set; }
    public bool IsEarlyLeave { get; set; }
    public bool IsHoliday { get; set; }
    public bool IsOnLeave { get; set; }
    public string Status { get; set; } = string.Empty;
}

// Late/Early Report DTOs
public class LateEarlyReportDto
{
    public DateTime StartDate { get; set; }
    public DateTime EndDate { get; set; }
    public int TotalEmployees { get; set; }
    public int EmployeesWithIssues { get; set; }
    public int TotalLateCount { get; set; }
    public int TotalLateMinutes { get; set; }
    public int TotalEarlyLeaveCount { get; set; }
    public int TotalEarlyMinutes { get; set; }
    public List<LateEarlyItemDto> Items { get; set; } = new();
}

public class LateEarlyItemDto
{
    public Guid EmployeeId { get; set; }
    public string EmployeeCode { get; set; } = string.Empty;
    public string EmployeeName { get; set; } = string.Empty;
    public string DepartmentName { get; set; } = string.Empty;
    public int LateCount { get; set; }
    public int TotalLateMinutes { get; set; }
    public int EarlyLeaveCount { get; set; }
    public int TotalEarlyMinutes { get; set; }
}

// Department Summary Report DTOs
public class DepartmentSummaryReportDto
{
    public int Year { get; set; }
    public int Month { get; set; }
    public int WorkingDays { get; set; }
    public int TotalDepartments { get; set; }
    public int TotalEmployees { get; set; }
    public List<DepartmentSummaryItemDto> Items { get; set; } = new();
}

public class DepartmentSummaryItemDto
{
    public Guid DepartmentId { get; set; }
    public string DepartmentName { get; set; } = string.Empty;
    public int EmployeeCount { get; set; }
    public int TotalAttendance { get; set; }
    public int TotalLateCount { get; set; }
    public double TotalWorkedHours { get; set; }
    public double AverageWorkedHoursPerDay { get; set; }
    public double AttendanceRate { get; set; }
}

// Overtime Report DTOs
public class OvertimeReportDto
{
    public DateTime StartDate { get; set; }
    public DateTime EndDate { get; set; }
    public int TotalEmployees { get; set; }
    public int EmployeesWithOvertime { get; set; }
    public int TotalOvertimeMinutes { get; set; }
    public double TotalOvertimeHours { get; set; }
    public List<OvertimeItemDto> Items { get; set; } = new();
}

public class OvertimeItemDto
{
    public Guid EmployeeId { get; set; }
    public string EmployeeCode { get; set; } = string.Empty;
    public string EmployeeName { get; set; } = string.Empty;
    public string DepartmentName { get; set; } = string.Empty;
    public int TotalOvertimeMinutes { get; set; }
    public double TotalOvertimeHours { get; set; }
    public int OvertimeDays { get; set; }
    public List<OvertimeDayDetailDto> Details { get; set; } = new();
}

public class OvertimeDayDetailDto
{
    public DateTime Date { get; set; }
    public DateTime CheckInTime { get; set; }
    public DateTime CheckOutTime { get; set; }
    public int WorkedMinutes { get; set; }
    public int OvertimeMinutes { get; set; }
}

public class LeaveSummaryReportDto
{
    public DateTime StartDate { get; set; }
    public DateTime EndDate { get; set; }
    public int TotalEmployees { get; set; }
    public int EmployeesWithLeave { get; set; }
    public int TotalLeaveRequests { get; set; }
    public double TotalLeaveDays { get; set; }
    public int ApprovedCount { get; set; }
    public int RejectedCount { get; set; }
    public int PendingCount { get; set; }
    public List<LeaveSummaryItemDto> Items { get; set; } = new();
}

public class LeaveSummaryItemDto
{
    public Guid EmployeeId { get; set; }
    public string EmployeeCode { get; set; } = string.Empty;
    public string EmployeeName { get; set; } = string.Empty;
    public string DepartmentName { get; set; } = string.Empty;
    public string LeaveType { get; set; } = string.Empty;
    public int TotalRequests { get; set; }
    public double TotalDays { get; set; }
    public double UsedDays { get; set; }
    public double RemainingDays { get; set; }
    public int ApprovedCount { get; set; }
    public int RejectedCount { get; set; }
    public int PendingCount { get; set; }
}

#endregion


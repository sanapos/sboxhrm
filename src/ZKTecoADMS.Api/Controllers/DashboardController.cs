using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Api.Models.Responses;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.DTOs.Dashboard;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Application.Queries.Dashboard.GetManagerDashboard;
using ZKTecoADMS.Application.Queries.Dashboard.GetEmployeeDashboard;
using ZKTecoADMS.Application.Queries.Dashboard.GetTodayShift;
using ZKTecoADMS.Application.Queries.Dashboard.GetNextShift;
using ZKTecoADMS.Application.Queries.Dashboard.GetCurrentAttendance;
using ZKTecoADMS.Application.Queries.Dashboard.GetAttendanceStats;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Services;

namespace ZKTecoADMS.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
public class DashboardController(
    IMediator mediator,
    ILogger<DashboardController> logger,
    ZKTecoDbContext dbContext
) : AuthenticatedControllerBase
{
    /// <summary>
    /// Get manager dashboard with core information
    /// </summary>
    /// <param name="date">Date for the dashboard data (optional, defaults to today)</param>
    /// <returns>Dashboard data with employees on leave, absent, late, and attendance rate</returns>
    [HttpGet("manager")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("Dashboard", ModulePermissionAction.View)]
    [ProducesResponseType(typeof(AppResponse<ManagerDashboardDto>), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    public async Task<ActionResult<AppResponse<ManagerDashboardDto>>> GetManagerDashboard(
        [FromQuery] DateTime? date = null)
    {
        try
        {
            // Default to VN-local today (server may run in UTC — DateTime.Today would be wrong).
            var targetDate = date?.Date ?? DateTime.UtcNow.AddHours(7).Date;

            var query = new GetManagerDashboardQuery(
                CurrentUserId,
                targetDate,
                CurrentUserRole,
                CurrentStoreId
            );

            var result = await mediator.Send(query);

            return Ok(result);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error retrieving manager dashboard data");
            return StatusCode(500, AppResponse<ManagerDashboardDto>.Fail("An error occurred while retrieving manager dashboard data"));
        }
    }

    // Employee Dashboard Endpoints

    /// <summary>
    /// Get complete employee dashboard data
    /// </summary>
    /// <param name="period">Period for attendance stats (week, month, year)</param>
    [HttpGet("employee")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("Dashboard", ModulePermissionAction.View)]
    [ProducesResponseType(typeof(AppResponse<EmployeeDashboardDto>), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    public async Task<ActionResult<AppResponse<EmployeeDashboardDto>>> GetEmployeeDashboard([FromQuery] string period = "week")
    {
        try
        {
            var query = new GetEmployeeDashboardQuery(CurrentUserId, period);
            var result = await mediator.Send(query);
            return Ok(result);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error retrieving employee dashboard");
            return StatusCode(500, AppResponse<EmployeeDashboardDto>.Fail("An error occurred while retrieving employee dashboard"));
        }
    }

    /// <summary>
    /// Get Current Shift information
    /// </summary>
    [HttpGet("shifts/today")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("Dashboard", ModulePermissionAction.View)]
    [ProducesResponseType(typeof(AppResponse<ShiftInfoDto>), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    public async Task<ActionResult<AppResponse<ShiftInfoDto>>> GetTodayShift()
    {
        try
        {
            var query = new GetTodayShiftQuery(CurrentUserId);
            var result = await mediator.Send(query);
            return Ok(result);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error retrieving Current Shift");
            return StatusCode(500, AppResponse<ShiftInfoDto>.Fail("An error occurred while retrieving Current Shift"));
        }
    }

    /// <summary>
    /// Get next upcoming shift
    /// </summary>
    [HttpGet("shifts/next")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("Dashboard", ModulePermissionAction.View)]
    [ProducesResponseType(typeof(AppResponse<ShiftInfoDto>), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    public async Task<ActionResult<AppResponse<ShiftInfoDto>>> GetNextShift()
    {
        try
        {
            var query = new GetNextShiftQuery(CurrentUserId);
            var result = await mediator.Send(query);
            return Ok(result);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error retrieving next shift");
            return StatusCode(500, AppResponse<ShiftInfoDto>.Fail("An error occurred while retrieving next shift"));
        }
    }

    /// <summary>
    /// Get current day attendance status
    /// </summary>
    [HttpGet("attendance/current")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("Dashboard", ModulePermissionAction.View)]
    [ProducesResponseType(typeof(AppResponse<AttendanceInfoDto>), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    public async Task<ActionResult<AppResponse<AttendanceInfoDto>>> GetCurrentAttendance()
    {
        try
        {
            var query = new GetCurrentAttendanceQuery(CurrentUserId);
            var result = await mediator.Send(query);
            return Ok(result);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error retrieving current attendance");
            return StatusCode(500, AppResponse<AttendanceInfoDto>.Fail("An error occurred while retrieving current attendance"));
        }
    }

    /// <summary>
    /// Get attendance statistics for a period
    /// </summary>
    /// <param name="period">Period for stats (week, month, year)</param>
    [HttpGet("attendance/stats")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("Dashboard", ModulePermissionAction.View)]
    [ProducesResponseType(typeof(AppResponse<AttendanceStatsDto>), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    public async Task<ActionResult<AppResponse<AttendanceStatsDto>>> GetAttendanceStats([FromQuery] string period = "week")
    {
        try
        {
            var query = new GetAttendanceStatsQuery(CurrentUserId, period);
            var result = await mediator.Send(query);
            return Ok(result);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error retrieving attendance stats");
            return StatusCode(500, AppResponse<AttendanceStatsDto>.Fail("An error occurred while retrieving attendance stats"));
        }
    }

    /// <summary>
    /// Get attendance trends for the last N days
    /// </summary>
    [HttpGet("attendance-trends")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("Dashboard", ModulePermissionAction.View)]
    public async Task<IActionResult> GetAttendanceTrends(
        [FromQuery] int days = 30,
        [FromQuery] Guid? branchId = null,
        [FromQuery] bool includeChildBranches = true)
    {
        try
        {
            var storeId = RequiredStoreId;
            days = Math.Clamp(days, 1, 90);
            var endDate = DateTime.UtcNow.AddHours(7).Date;
            var startDate = endDate.AddDays(-days);
            var utcRangeStart = startDate.AddHours(-7);
            var utcRangeEnd = endDate.AddDays(1).AddHours(-7);

            // Load employees with ApplicationUserId for WorkSchedule lookup
            var employeesQuery = dbContext.Employees
                .Where(e => e.StoreId == storeId && e.Deleted == null);
            employeesQuery = await BranchQueryHelper.ApplyBranchFilterAsync(
                employeesQuery, dbContext, storeId, branchId, includeChildBranches);

            var employeeData = await employeesQuery
                .Select(e => new { e.EmployeeCode, e.ApplicationUserId, e.FirstName, e.LastName })
                .ToListAsync();

            var employeeCodes = employeeData.Select(e => e.EmployeeCode).ToList();
            // PIN → ApplicationUserId mapping (for shift lookup)
            var pinToUserId = employeeData
                .Where(e => e.ApplicationUserId.HasValue)
                .ToDictionary(e => e.EmployeeCode, e => e.ApplicationUserId!.Value);
            // PIN → display name mapping (Vietnamese: LastName FirstName)
            var pinToName = employeeData
                .ToDictionary(e => e.EmployeeCode, e => $"{e.LastName} {e.FirstName}".Trim());

            var attendances = await dbContext.AttendanceLogs
                .Where(a => a.Device != null && a.Device.StoreId == storeId
                    && a.AttendanceTime >= utcRangeStart
                    && a.AttendanceTime < utcRangeEnd
                    && employeeCodes.Contains(a.PIN))
                .Select(a => new { a.PIN, a.AttendanceTime, a.AttendanceState })
                .ToListAsync();

            // AttendanceTime is stored as UTC (EnableLegacyTimestampBehavior=true, Kind=Unspecified).
            // Convert to VN (UTC+7) once here so every Date / TimeOfDay comparison below is in VN.
            // Earlier code used `a.AttendanceTime` directly here while the query window was UTC —
            // that made trend data drift by 7h (evening punches landed on the next day's bucket).
            var vnAttendances = attendances
                .Select(a => new { a.PIN, VnTime = a.AttendanceTime.AddHours(7), a.AttendanceState })
                .ToList();

            // Load ShiftTemplates for the store (used as fallback when no WorkSchedule exists)
            var shiftTemplates = await dbContext.ShiftTemplates
                .Where(st => st.StoreId == storeId && st.IsActive)
                .Select(st => new {
                    st.Name, st.StartTime, st.EndTime,
                    st.LateGraceMinutes, st.EarlyLeaveGraceMinutes, st.EarlyCheckInMinutes
                })
                .ToListAsync();

            // Load WorkSchedules with ShiftTemplate for the date range
            var userIds = pinToUserId.Values.ToList();
            var workScheduleData = await dbContext.WorkSchedules
                .Where(ws => ws.Date >= startDate && ws.Date < endDate.AddDays(1)
                    && userIds.Contains(ws.EmployeeUserId))
                .Select(ws => new {
                    ws.EmployeeUserId,
                    Date = ws.Date.Date,
                    ws.IsDayOff,
                    OverrideStart = ws.StartTime,
                    OverrideEnd = ws.EndTime,
                    ShiftStart = ws.Shift != null ? ws.Shift.StartTime : (TimeSpan?)null,
                    ShiftEnd = ws.Shift != null ? (TimeSpan?)ws.Shift.EndTime : null,
                    LateGraceMinutes = ws.Shift != null ? ws.Shift.LateGraceMinutes : 5,
                    EarlyLeaveGraceMinutes = ws.Shift != null ? ws.Shift.EarlyLeaveGraceMinutes : 5,
                    ShiftName = ws.Shift != null ? ws.Shift.Name : null
                })
                .ToListAsync();

            // Index: (employeeUserId, date) → schedule info
            var scheduleIndex = workScheduleData
                .GroupBy(ws => (ws.EmployeeUserId, ws.Date))
                .ToDictionary(g => g.Key, g => g.First());

            var defaultStart = new TimeSpan(8, 30, 0);
            var trends = new List<object>();

            for (var d = startDate; d <= endDate; d = d.AddDays(1))
            {
                if (d.DayOfWeek == DayOfWeek.Saturday || d.DayOfWeek == DayOfWeek.Sunday)
                    continue;

                var dayAttendances = vnAttendances.Where(a => a.VnTime.Date == d).ToList();
                var presentPins = dayAttendances.Select(a => a.PIN).Distinct().ToList();
                var lateCount = 0;
                var onTimeCount = 0;
                var earlyLeaveCount = 0;

                // shiftName → (present, late, earlyLeave)
                var shiftStats = new Dictionary<string, (int Present, int Late, int EarlyLeave)>();
                var lateEmps = new List<object>();
                var earlyEmps = new List<object>();

                foreach (var pin in presentPins)
                {
                    var checkIn = dayAttendances
                        .Where(a => a.PIN == pin && a.AttendanceState == AttendanceStates.CheckIn)
                        .OrderBy(a => a.VnTime)
                        .FirstOrDefault();
                    if (checkIn == null) continue;

                    // Resolve per-employee shift start/end time
                    var threshold = defaultStart;
                    var graceMin = 5;
                    var shiftLabel = (string?)null;
                    TimeSpan? shiftEnd = null;
                    var earlyGraceMin = 5;

                    // Primary: WorkSchedule lookup
                    if (pinToUserId.TryGetValue(pin, out var uid)
                        && scheduleIndex.TryGetValue((uid, d), out var sched)
                        && !sched.IsDayOff)
                    {
                        threshold = sched.OverrideStart ?? sched.ShiftStart ?? defaultStart;
                        graceMin = sched.LateGraceMinutes;
                        shiftLabel = sched.ShiftName ?? "Ca khác";
                        shiftEnd = sched.OverrideEnd ?? sched.ShiftEnd;
                        earlyGraceMin = sched.EarlyLeaveGraceMinutes;
                    }

                    // Fallback: match check-in time to nearest active ShiftTemplate
                    if (shiftLabel == null && shiftTemplates.Count > 0)
                    {
                        var checkInMins = checkIn.VnTime.TimeOfDay.TotalMinutes;
                        var best = shiftTemplates
                            .Where(st => {
                                var windowStart = st.StartTime.TotalMinutes - st.EarlyCheckInMinutes;
                                return checkInMins >= windowStart && checkInMins <= st.StartTime.TotalMinutes + 180;
                            })
                            .OrderBy(st => Math.Abs(st.StartTime.TotalMinutes - checkInMins))
                            .FirstOrDefault();
                        if (best != null)
                        {
                            shiftLabel = best.Name;
                            threshold = best.StartTime;
                            graceMin = best.LateGraceMinutes;
                            shiftEnd = best.EndTime;
                            earlyGraceMin = best.EarlyLeaveGraceMinutes;
                        }
                    }

                    shiftLabel ??= "Không xếp ca";

                    if (!shiftStats.ContainsKey(shiftLabel))
                        shiftStats[shiftLabel] = (0, 0, 0);

                    var isLate = checkIn.VnTime.TimeOfDay > threshold + TimeSpan.FromMinutes(graceMin);

                    // Kiểm tra về sớm: lấy lần checkout cuối cùng trong ngày
                    var checkOut = dayAttendances
                        .Where(a => a.PIN == pin && a.AttendanceState == AttendanceStates.CheckOut)
                        .OrderByDescending(a => a.VnTime)
                        .FirstOrDefault();
                    var isEarly = checkOut != null && shiftEnd.HasValue
                        && checkOut.VnTime.TimeOfDay < shiftEnd.Value - TimeSpan.FromMinutes(earlyGraceMin);

                    if (isLate) lateCount++;
                    else onTimeCount++;
                    if (isEarly) earlyLeaveCount++;

                    var cur = shiftStats[shiftLabel];
                    shiftStats[shiftLabel] = (
                        cur.Present + 1,
                        cur.Late + (isLate ? 1 : 0),
                        cur.EarlyLeave + (isEarly ? 1 : 0)
                    );

                    // Track employee details for late/early lists
                    var empName = pinToName.TryGetValue(pin, out var n2) ? n2 : pin;
                    if (isLate)
                    {
                        var lateMins = (int)(checkIn.VnTime.TimeOfDay - threshold - TimeSpan.FromMinutes(graceMin)).TotalMinutes;
                        lateEmps.Add(new { pin, name = empName, checkIn = checkIn.VnTime.ToString("HH:mm"), lateMinutes = lateMins, shift = shiftLabel });
                    }
                    if (isEarly && checkOut != null && shiftEnd.HasValue)
                    {
                        var earlyMins = (int)(shiftEnd.Value - TimeSpan.FromMinutes(earlyGraceMin) - checkOut.VnTime.TimeOfDay).TotalMinutes;
                        earlyEmps.Add(new { pin, name = empName, checkOut = checkOut.VnTime.ToString("HH:mm"), earlyMinutes = earlyMins, shift = shiftLabel });
                    }
                }

                var totalEmp = employeeCodes.Count;
                var presentCount = presentPins.Count;
                var absentCount = Math.Max(0, totalEmp - presentCount);
                var rate = totalEmp > 0 ? Math.Round((double)presentCount / totalEmp * 100, 1) : 0.0;

                trends.Add(new
                {
                    date = d.ToString("yyyy-MM-dd"),
                    present = presentCount,
                    onTime = onTimeCount,
                    late = lateCount,
                    earlyLeave = earlyLeaveCount,
                    absent = absentCount,
                    total = totalEmp,
                    attendanceRate = rate,
                    shiftBreakdown = shiftStats
                        .OrderBy(kv => kv.Key)
                        .Select(kv => new { shiftName = kv.Key, present = kv.Value.Present, late = kv.Value.Late, earlyLeave = kv.Value.EarlyLeave })
                        .ToList(),
                    lateEmployees = lateEmps,
                    earlyEmployees = earlyEmps
                });
            }

            return Ok(AppResponse<object>.Success(trends));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error getting attendance trends");
            return StatusCode(500, AppResponse<object>.Fail("Error getting attendance trends"));
        }
    }
}

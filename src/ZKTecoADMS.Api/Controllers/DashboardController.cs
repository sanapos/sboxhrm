using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
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
    [ProducesResponseType(typeof(AppResponse<ManagerDashboardDto>), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    public async Task<ActionResult<AppResponse<ManagerDashboardDto>>> GetManagerDashboard(
        [FromQuery] DateTime? date = null)
    {
        try
        {
            var targetDate = date ?? DateTime.Today;

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
    public async Task<IActionResult> GetAttendanceTrends([FromQuery] int days = 30)
    {
        try
        {
            var storeId = RequiredStoreId;
            days = Math.Clamp(days, 1, 90); // Cap at 90 days to prevent loading excessive data
            var endDate = DateTime.Today;
            var startDate = endDate.AddDays(-days);

            var employees = await dbContext.Employees
                .Where(e => e.StoreId == storeId && e.Deleted == null)
                .Select(e => e.EmployeeCode)
                .ToListAsync();

            var employeeCodes = employees;

            var attendances = await dbContext.AttendanceLogs
                .Where(a => a.Device != null && a.Device.StoreId == storeId
                    && a.AttendanceTime >= startDate
                    && a.AttendanceTime <= endDate.AddDays(1)
                    && employeeCodes.Contains(a.PIN))
                .Select(a => new { a.PIN, a.AttendanceTime, a.AttendanceState })
                .ToListAsync();

            var lateThreshold = new TimeSpan(8, 30, 0);
            var trends = new List<object>();

            for (var d = startDate; d <= endDate; d = d.AddDays(1))
            {
                if (d.DayOfWeek == DayOfWeek.Saturday || d.DayOfWeek == DayOfWeek.Sunday)
                    continue;

                var dayAttendances = attendances.Where(a => a.AttendanceTime.Date == d).ToList();
                var presentPins = dayAttendances.Select(a => a.PIN).Distinct().ToList();
                var lateCount = 0;

                foreach (var pin in presentPins)
                {
                    var checkIn = dayAttendances
                        .Where(a => a.PIN == pin && a.AttendanceState == AttendanceStates.CheckIn)
                        .OrderBy(a => a.AttendanceTime)
                        .FirstOrDefault();
                    if (checkIn?.AttendanceTime.TimeOfDay > lateThreshold)
                        lateCount++;
                }

                trends.Add(new
                {
                    date = d.ToString("yyyy-MM-dd"),
                    present = presentPins.Count,
                    absent = employees.Count - presentPins.Count,
                    late = lateCount,
                    total = employees.Count
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

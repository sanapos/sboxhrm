using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using System.Text;
using ClosedXML.Excel;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
public class ReportsController(
    ZKTecoDbContext dbContext,
    ILogger<ReportsController> logger
) : AuthenticatedControllerBase
{
    #region Daily Attendance Report

    /// <summary>
    /// Get daily attendance report
    /// </summary>
    [HttpGet("attendance/daily")]
    public async Task<ActionResult<AppResponse<DailyAttendanceReportDto>>> GetDailyAttendanceReport(
        [FromQuery] DateTime? date = null,
        [FromQuery] string? department = null,
        [FromQuery] string? employeeCode = null)
    {
        try
        {
            var targetDate = date ?? DateTime.Today;
            var storeId = RequiredStoreId;

            // Get all employees (filter by Deleted == null for active)
            var employeesQuery = dbContext.Employees
                .Where(e => e.StoreId == storeId && e.Deleted == null);
            
            if (!string.IsNullOrEmpty(department))
            {
                employeesQuery = employeesQuery.Where(e => !string.IsNullOrEmpty(e.Department) && e.Department.Contains(department));
            }
            
            if (!string.IsNullOrEmpty(employeeCode))
            {
                employeesQuery = employeesQuery.Where(e => e.EmployeeCode.Contains(employeeCode));
            }

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

            // Get attendances for the date (filter by Device.StoreId) — use Select projection
            var attendances = await dbContext.AttendanceLogs
                .Where(a => a.Device != null && a.Device.StoreId == storeId 
                    && a.AttendanceTime.Date == targetDate.Date
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

            // Build schedule lookup: EmployeeId -> WorkSchedule
            var scheduleMap = workSchedules
                .GroupBy(ws => ws.EmployeeUserId)
                .ToDictionary(g => g.Key, g => g.First());

            // Build report data
            var reportItems = new List<DailyAttendanceItemDto>();
            var totalLate = 0;
            var totalEarlyLeave = 0;
            var totalOnTime = 0;
            var totalAbsent = 0;
            var totalOnLeave = 0;
            var totalNotScheduled = 0;

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

                // Check work schedule
                scheduleMap.TryGetValue(employee.Id, out var schedule);
                var hasSchedule = schedule != null;
                var isDayOff = schedule?.IsDayOff ?? false;

                // Determine expected start/end from shift template or schedule override
                var expectedStart = schedule?.StartTime ?? schedule?.Shift?.StartTime ?? defaultExpectedStart;
                var expectedEnd = schedule?.EndTime ?? schedule?.Shift?.EndTime ?? defaultExpectedEnd;

                // Check if on leave — O(1) HashSet lookup
                var isOnLeave = employee.ApplicationUserId.HasValue && 
                    leaveUserIds.Contains(employee.ApplicationUserId.Value);
                
                // Calculate status
                var status = "Vắng mặt";
                var lateMinutes = 0;
                var earlyLeaveMinutes = 0;

                if (isOnLeave)
                {
                    status = "Nghỉ phép";
                    totalOnLeave++;
                }
                else if (!hasSchedule)
                {
                    // No work schedule assigned for today — not counted as absent
                    status = "Không có lịch";
                    totalNotScheduled++;
                }
                else if (isDayOff)
                {
                    // Scheduled as day off — not counted as absent
                    status = "Ngày nghỉ";
                    totalNotScheduled++;
                }
                else if (checkIn != null)
                {
                    var checkInTime = checkIn.AttendanceTime.TimeOfDay;
                    if (checkInTime > expectedStart)
                    {
                        lateMinutes = (int)(checkInTime - expectedStart).TotalMinutes;
                        status = "Đi muộn";
                        totalLate++;
                    }
                    else
                    {
                        status = "Đúng giờ";
                        totalOnTime++;
                    }

                    if (checkOut != null)
                    {
                        var checkOutTime = checkOut.AttendanceTime.TimeOfDay;
                        if (checkOutTime < expectedEnd)
                        {
                            earlyLeaveMinutes = (int)(expectedEnd - checkOutTime).TotalMinutes;
                            if (status == "Đúng giờ")
                            {
                                status = "Về sớm";
                            }
                            else
                            {
                                status += " + Về sớm";
                            }
                            totalEarlyLeave++;
                        }
                    }
                }
                else
                {
                    // Has schedule, not day off, no check-in, not on leave → truly absent
                    totalAbsent++;
                }

                var workedMinutes = 0;
                if (checkIn != null && checkOut != null)
                {
                    workedMinutes = (int)(checkOut.AttendanceTime - checkIn.AttendanceTime).TotalMinutes;
                }

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
                    Note = checkIn?.Note ?? checkOut?.Note
                });
            }

            var scheduledCount = employees.Count - totalNotScheduled;
            var report = new DailyAttendanceReportDto
            {
                Date = targetDate,
                TotalEmployees = employees.Count,
                Present = totalOnTime + totalLate + totalEarlyLeave,
                OnTime = totalOnTime,
                Late = totalLate,
                EarlyLeave = totalEarlyLeave,
                Absent = totalAbsent,
                OnLeave = totalOnLeave,
                AttendanceRate = scheduledCount > 0 
                    ? Math.Round((double)(totalOnTime + totalLate + totalEarlyLeave) / scheduledCount * 100, 2) 
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
    public async Task<ActionResult<AppResponse<MonthlyAttendanceReportDto>>> GetMonthlyAttendanceReport(
        [FromQuery] int? year = null,
        [FromQuery] int? month = null,
        [FromQuery] string? department = null)
    {
        try
        {
            var targetYear = year ?? DateTime.Now.Year;
            var targetMonth = month ?? DateTime.Now.Month;
            var storeId = RequiredStoreId;

            var startDate = new DateTime(targetYear, targetMonth, 1);
            var endDate = startDate.AddMonths(1).AddDays(-1);

            // Get employees
            var employeesQuery = dbContext.Employees
                .Where(e => e.StoreId == storeId && e.Deleted == null);
            
            if (!string.IsNullOrEmpty(department))
            {
                employeesQuery = employeesQuery.Where(e => !string.IsNullOrEmpty(e.Department) && e.Department.Contains(department));
            }

            var employees = await employeesQuery.ToListAsync();

            var employeeCodes = employees.Select(e => e.EmployeeCode).ToList();

            // Get attendances for the month (filter by Device.StoreId) — use Select projection
            var attendances = await dbContext.AttendanceLogs
                .Where(a => a.Device != null && a.Device.StoreId == storeId 
                    && a.AttendanceTime >= startDate 
                    && a.AttendanceTime <= endDate.AddDays(1)
                    && employeeCodes.Contains(a.PIN))
                .Select(a => new { a.PIN, a.AttendanceTime, a.AttendanceState })
                .ToListAsync();

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

            // Default late threshold: 8:30 AM
            var lateThreshold = new TimeSpan(8, 30, 0);

            foreach (var employee in employees)
            {
                // O(1) lookup instead of scanning entire list
                var empAttendances = attendanceByPin[employee.EmployeeCode].ToList();
                
                // Get leaves for this employee — O(1) lookup (ILookup returns empty for missing keys)
                var empLeaveUserId = employee.ApplicationUserId ?? Guid.Empty;
                var empLeaves = leavesByUserId[empLeaveUserId];

                // Count working days attended
                var daysPresent = empAttendances
                    .Select(a => a.AttendanceTime.Date)
                    .Distinct()
                    .Count();

                // Count late arrivals
                var lateDays = empAttendances
                    .Where(a => a.AttendanceState == AttendanceStates.CheckIn)
                    .GroupBy(a => a.AttendanceTime.Date)
                    .Count(g => g.OrderBy(a => a.AttendanceTime).First().AttendanceTime.TimeOfDay > lateThreshold);

                // Count leave days for this employee
                var leaveDays = 0;
                foreach (var leave in empLeaves)
                {
                    var leaveStart = leave.StartDate < startDate ? startDate : leave.StartDate;
                    var leaveEnd = leave.EndDate > endDate ? endDate : leave.EndDate;
                    leaveDays += (int)(leaveEnd - leaveStart).TotalDays + 1;
                }

                // Calculate total worked hours
                var totalWorkedMinutes = 0;
                var groupedByDate = empAttendances.GroupBy(a => a.AttendanceTime.Date);
                foreach (var dayGroup in groupedByDate)
                {
                    var dayCheckIn = dayGroup.Where(a => a.AttendanceState == AttendanceStates.CheckIn)
                        .OrderBy(a => a.AttendanceTime).FirstOrDefault();
                    var dayCheckOut = dayGroup.Where(a => a.AttendanceState == AttendanceStates.CheckOut)
                        .OrderByDescending(a => a.AttendanceTime).FirstOrDefault();
                    
                    if (dayCheckIn != null && dayCheckOut != null)
                    {
                        totalWorkedMinutes += (int)(dayCheckOut.AttendanceTime - dayCheckIn.AttendanceTime).TotalMinutes;
                    }
                }

                var absentDays = workingDays - daysPresent - leaveDays;
                if (absentDays < 0) absentDays = 0;

                reportItems.Add(new MonthlyAttendanceItemDto
                {
                    EmployeeId = employee.Id,
                    EmployeeCode = employee.EmployeeCode,
                    EmployeeName = $"{employee.LastName} {employee.FirstName}".Trim(),
                    DepartmentName = employee.Department ?? "N/A",
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
                        && l.Status == LeaveStatus.Approved)
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

                var status = "Vắng mặt";
                var workedMinutes = 0;
                var isLate = false;
                var isEarlyLeave = false;

                if (isHoliday)
                {
                    status = "Ngày lễ";
                }
                else if (isOnLeave)
                {
                    status = "Nghỉ phép";
                    totalLeaveDays++;
                }
                else if (checkIn != null)
                {
                    totalPresentDays++;
                    var checkInTime = checkIn.AttendanceTime.TimeOfDay;
                    
                    if (checkInTime > lateThreshold)
                    {
                        isLate = true;
                        totalLateDays++;
                        status = "Đi muộn";
                    }
                    else
                    {
                        status = "Đúng giờ";
                    }

                    if (checkOut != null)
                    {
                        workedMinutes = (int)(checkOut.AttendanceTime - checkIn.AttendanceTime).TotalMinutes;
                        totalWorkedMinutes += workedMinutes;
                        
                        if (checkOut.AttendanceTime.TimeOfDay < earlyLeaveThreshold)
                        {
                            isEarlyLeave = true;
                            totalEarlyLeaveDays++;
                            if (isLate) status += " + Về sớm";
                            else status = "Về sớm";
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
    public async Task<ActionResult<AppResponse<LateEarlyReportDto>>> GetLateEarlyReport(
        [FromQuery] DateTime? startDate = null,
        [FromQuery] DateTime? endDate = null,
        [FromQuery] string? department = null)
    {
        try
        {
            var storeId = RequiredStoreId;
            var start = startDate ?? DateTime.Today.AddMonths(-1);
            var end = endDate ?? DateTime.Today;

            var employeesQuery = dbContext.Employees
                .Where(e => e.StoreId == storeId && e.Deleted == null);
            
            if (!string.IsNullOrEmpty(department))
            {
                employeesQuery = employeesQuery.Where(e => !string.IsNullOrEmpty(e.Department) && e.Department.Contains(department));
            }

            var employees = await employeesQuery.ToListAsync();

            var employeeCodes = employees.Select(e => e.EmployeeCode).ToList();

            var attendances = await dbContext.AttendanceLogs
                .Where(a => a.Device != null && a.Device.StoreId == storeId 
                    && a.AttendanceTime >= start 
                    && a.AttendanceTime <= end.AddDays(1)
                    && employeeCodes.Contains(a.PIN))
                .Select(a => new { a.PIN, a.AttendanceTime, a.AttendanceState })
                .ToListAsync();

            // Build attendance lookup by PIN for O(1) access
            var attendanceByPin = attendances.ToLookup(a => a.PIN);

            var reportItems = new List<LateEarlyItemDto>();
            var totalLateCount = 0;
            var totalEarlyCount = 0;
            var totalLateMinutes = 0;
            var totalEarlyMinutes = 0;

            // Default times: 8:30 AM start, 6:00 PM end
            var lateThreshold = new TimeSpan(8, 30, 0);
            var earlyLeaveThreshold = new TimeSpan(18, 0, 0);

            foreach (var employee in employees)
            {
                // O(1) lookup instead of scanning entire list
                var empAttendances = attendanceByPin[employee.EmployeeCode].ToList();
                var groupedByDate = empAttendances.GroupBy(a => a.AttendanceTime.Date);

                var lateCount = 0;
                var earlyCount = 0;
                var lateMins = 0;
                var earlyMins = 0;

                foreach (var dayGroup in groupedByDate)
                {
                    var checkIn = dayGroup.Where(a => a.AttendanceState == AttendanceStates.CheckIn)
                        .OrderBy(a => a.AttendanceTime).FirstOrDefault();
                    var checkOut = dayGroup.Where(a => a.AttendanceState == AttendanceStates.CheckOut)
                        .OrderByDescending(a => a.AttendanceTime).FirstOrDefault();

                    // Check late
                    if (checkIn?.AttendanceTime.TimeOfDay > lateThreshold)
                    {
                        lateCount++;
                        lateMins += (int)(checkIn.AttendanceTime.TimeOfDay - lateThreshold).TotalMinutes;
                    }

                    // Check early leave
                    if (checkOut?.AttendanceTime.TimeOfDay < earlyLeaveThreshold)
                    {
                        earlyCount++;
                        earlyMins += (int)(earlyLeaveThreshold - checkOut.AttendanceTime.TimeOfDay).TotalMinutes;
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
                    var groupedByDate = empAtts.GroupBy(a => a.AttendanceTime.Date);

                    foreach (var dayGroup in groupedByDate)
                    {
                        attendedDays++;
                        var checkIn = dayGroup.Where(a => a.AttendanceState == AttendanceStates.CheckIn)
                            .OrderBy(a => a.AttendanceTime).FirstOrDefault();
                        var checkOut = dayGroup.Where(a => a.AttendanceState == AttendanceStates.CheckOut)
                            .OrderByDescending(a => a.AttendanceTime).FirstOrDefault();

                        if (checkIn?.AttendanceTime.TimeOfDay > lateThreshold)
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
    public async Task<ActionResult<AppResponse<OvertimeReportDto>>> GetOvertimeReport(
        [FromQuery] DateTime? startDate = null,
        [FromQuery] DateTime? endDate = null,
        [FromQuery] string? department = null,
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
            
            if (!string.IsNullOrEmpty(department))
            {
                employeesQuery = employeesQuery.Where(e => !string.IsNullOrEmpty(e.Department) && e.Department.Contains(department));
            }

            var employees = await employeesQuery.ToListAsync();

            var employeeCodes = employees.Select(e => e.EmployeeCode).ToList();

            var attendances = await dbContext.AttendanceLogs
                .Where(a => a.Device != null && a.Device.StoreId == storeId 
                    && a.AttendanceTime >= start 
                    && a.AttendanceTime <= end.AddDays(1)
                    && employeeCodes.Contains(a.PIN))
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
                        var workedMinutes = (int)(checkOut.AttendanceTime - checkIn.AttendanceTime).TotalMinutes;
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
    public async Task<ActionResult<AppResponse<LeaveSummaryReportDto>>> GetLeaveSummaryReport(
        [FromQuery] DateTime? startDate = null,
        [FromQuery] DateTime? endDate = null,
        [FromQuery] string? department = null)
    {
        try
        {
            var storeId = RequiredStoreId;
            var start = startDate ?? new DateTime(DateTime.Now.Year, 1, 1);
            var end = endDate ?? DateTime.Today;

            var employeesQuery = dbContext.Employees
                .Where(e => e.StoreId == storeId && e.Deleted == null);
            
            if (!string.IsNullOrEmpty(department))
            {
                employeesQuery = employeesQuery.Where(e => !string.IsNullOrEmpty(e.Department) && e.Department.Contains(department));
            }

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

                var usedDays = 0;
                foreach (var leave in approved)
                {
                    var leaveStart = leave.StartDate < start ? start : leave.StartDate;
                    var leaveEnd = leave.EndDate > end ? end : leave.EndDate;
                    usedDays += (int)(leaveEnd - leaveStart).TotalDays + 1;
                }

                totalLeaveRequests += empLeaves.Count;
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
                    TotalRequests = empLeaves.Count,
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
    public async Task<IActionResult> ExportDailyReport(
        [FromQuery] DateTime? date = null,
        [FromQuery] string format = "csv")
    {
        var reportResult = await GetDailyAttendanceReport(date);
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
            csv.AppendLine($"{stt++},\"{item.EmployeeCode}\",\"{item.EmployeeName}\",\"{item.DepartmentName}\",\"{item.CheckInTime:HH:mm}\",\"{item.CheckOutTime:HH:mm}\",{item.LateMinutes},{item.EarlyLeaveMinutes},{item.WorkedMinutes},\"{item.Status}\",\"{item.Note}\"");
        }

        var bytes = Encoding.UTF8.GetPreamble().Concat(Encoding.UTF8.GetBytes(csv.ToString())).ToArray();
        return File(bytes, "text/csv; charset=utf-8", $"bao_cao_cham_cong_{report.Date:yyyyMMdd}.csv");
    }

    /// <summary>
    /// Export monthly attendance report to CSV
    /// </summary>
    [HttpGet("export/monthly")]
    public async Task<IActionResult> ExportMonthlyReport(
        [FromQuery] int? year = null,
        [FromQuery] int? month = null,
        [FromQuery] string format = "csv")
    {
        var reportResult = await GetMonthlyAttendanceReport(year, month);
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
        csv.AppendLine("STT,Mã NV,Họ tên,Phòng ban,Ngày làm,Ngày muộn,Ngày nghỉ,Ngày vắng,Số giờ làm,Tỷ lệ CC (%)");
        
        var stt = 1;
        foreach (var item in report.Items)
        {
            csv.AppendLine($"{stt++},\"{item.EmployeeCode}\",\"{item.EmployeeName}\",\"{item.DepartmentName}\",{item.TotalDaysWorked},{item.TotalLateDays},{item.TotalLeaveDays},{item.TotalAbsentDays},{item.TotalWorkedHours},{item.AttendanceRate}");
        }

        var bytes = Encoding.UTF8.GetPreamble().Concat(Encoding.UTF8.GetBytes(csv.ToString())).ToArray();
        return File(bytes, "text/csv; charset=utf-8", $"bao_cao_thang_{report.Year}_{report.Month:D2}.csv");
    }

    /// <summary>
    /// Export late/early report to CSV
    /// </summary>
    [HttpGet("export/late-early")]
    public async Task<IActionResult> ExportLateEarlyReport(
        [FromQuery] DateTime? startDate = null,
        [FromQuery] DateTime? endDate = null,
        [FromQuery] string format = "csv")
    {
        var reportResult = await GetLateEarlyReport(startDate, endDate);
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
    public async Task<IActionResult> ExportDailyReportExcel([FromQuery] DateTime? date = null)
    {
        try
        {
            var reportResult = await GetDailyAttendanceReport(date);
            if (reportResult.Result is not OkObjectResult okResult 
                || okResult.Value is not AppResponse<DailyAttendanceReportDto> response 
                || response.Data == null)
            {
                return BadRequest("Failed to generate report");
            }

            var report = response.Data;

            using var workbook = new XLWorkbook();
            var worksheet = workbook.Worksheets.Add("Báo cáo chấm công");

            // Title
            worksheet.Cell(1, 1).Value = "BÁO CÁO CHẤM CÔNG NGÀY";
            worksheet.Range(1, 1, 1, 11).Merge();
            worksheet.Cell(1, 1).Style
                .Font.SetBold(true)
                .Font.SetFontSize(16)
                .Alignment.SetHorizontal(XLAlignmentHorizontalValues.Center);

            worksheet.Cell(2, 1).Value = $"Ngày: {report.Date:dd/MM/yyyy}";
            worksheet.Range(2, 1, 2, 11).Merge();
            worksheet.Cell(2, 1).Style.Alignment.SetHorizontal(XLAlignmentHorizontalValues.Center);

            // Summary
            worksheet.Cell(4, 1).Value = "Tổng số NV:";
            worksheet.Cell(4, 2).Value = report.TotalEmployees;
            worksheet.Cell(4, 3).Value = "Có mặt:";
            worksheet.Cell(4, 4).Value = report.Present;
            worksheet.Cell(4, 5).Value = "Đi muộn:";
            worksheet.Cell(4, 6).Value = report.Late;
            worksheet.Cell(4, 7).Value = "Về sớm:";
            worksheet.Cell(4, 8).Value = report.EarlyLeave;
            worksheet.Cell(4, 9).Value = "Vắng:";
            worksheet.Cell(4, 10).Value = report.Absent;

            // Headers
            var headerRow = 6;
            var headers = new[] { "STT", "Mã NV", "Họ tên", "Phòng ban", "Giờ vào", "Giờ ra", "Muộn (phút)", "Về sớm (phút)", "Làm (phút)", "Trạng thái", "Ghi chú" };
            for (int i = 0; i < headers.Length; i++)
            {
                worksheet.Cell(headerRow, i + 1).Value = headers[i];
            }
            worksheet.Range(headerRow, 1, headerRow, headers.Length).Style
                .Font.SetBold(true)
                .Fill.SetBackgroundColor(XLColor.LightBlue)
                .Border.SetOutsideBorder(XLBorderStyleValues.Thin);

            // Data
            var row = headerRow + 1;
            var stt = 1;
            foreach (var item in report.Items)
            {
                worksheet.Cell(row, 1).Value = stt++;
                worksheet.Cell(row, 2).Value = item.EmployeeCode;
                worksheet.Cell(row, 3).Value = item.EmployeeName;
                worksheet.Cell(row, 4).Value = item.DepartmentName;
                worksheet.Cell(row, 5).Value = item.CheckInTime?.ToString("HH:mm") ?? "-";
                worksheet.Cell(row, 6).Value = item.CheckOutTime?.ToString("HH:mm") ?? "-";
                worksheet.Cell(row, 7).Value = item.LateMinutes;
                worksheet.Cell(row, 8).Value = item.EarlyLeaveMinutes;
                worksheet.Cell(row, 9).Value = item.WorkedMinutes;
                worksheet.Cell(row, 10).Value = item.Status;
                worksheet.Cell(row, 11).Value = item.Note ?? "";

                // Color coding for status
                var statusCell = worksheet.Cell(row, 10);
                switch (item.Status)
                {
                    case "Đúng giờ":
                        statusCell.Style.Fill.SetBackgroundColor(XLColor.LightGreen);
                        break;
                    case "Đi muộn":
                    case string s when s.Contains("Đi muộn"):
                        statusCell.Style.Fill.SetBackgroundColor(XLColor.LightSalmon);
                        break;
                    case "Vắng mặt":
                        statusCell.Style.Fill.SetBackgroundColor(XLColor.LightPink);
                        break;
                }

                row++;
            }

            // Auto-fit columns
            worksheet.Columns().AdjustToContents();

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
    public async Task<IActionResult> ExportMonthlyReportExcel(
        [FromQuery] int? year = null,
        [FromQuery] int? month = null)
    {
        try
        {
            var reportResult = await GetMonthlyAttendanceReport(year, month);
            if (reportResult.Result is not OkObjectResult okResult 
                || okResult.Value is not AppResponse<MonthlyAttendanceReportDto> response 
                || response.Data == null)
            {
                return BadRequest("Failed to generate report");
            }

            var report = response.Data;

            using var workbook = new XLWorkbook();
            var worksheet = workbook.Worksheets.Add("Báo cáo tháng");

            // Title
            worksheet.Cell(1, 1).Value = "BÁO CÁO CHẤM CÔNG THÁNG";
            worksheet.Range(1, 1, 1, 10).Merge();
            worksheet.Cell(1, 1).Style
                .Font.SetBold(true)
                .Font.SetFontSize(16)
                .Alignment.SetHorizontal(XLAlignmentHorizontalValues.Center);

            worksheet.Cell(2, 1).Value = $"Tháng {report.Month}/{report.Year} - Số ngày làm việc: {report.WorkingDays}";
            worksheet.Range(2, 1, 2, 10).Merge();
            worksheet.Cell(2, 1).Style.Alignment.SetHorizontal(XLAlignmentHorizontalValues.Center);

            // Headers
            var headerRow = 4;
            var headers = new[] { "STT", "Mã NV", "Họ tên", "Phòng ban", "Ngày làm", "Ngày muộn", "Ngày nghỉ", "Ngày vắng", "Giờ làm", "Tỷ lệ (%)" };
            for (int i = 0; i < headers.Length; i++)
            {
                worksheet.Cell(headerRow, i + 1).Value = headers[i];
            }
            worksheet.Range(headerRow, 1, headerRow, headers.Length).Style
                .Font.SetBold(true)
                .Fill.SetBackgroundColor(XLColor.LightGreen)
                .Border.SetOutsideBorder(XLBorderStyleValues.Thin);

            // Data
            var row = headerRow + 1;
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

            // Auto-fit columns
            worksheet.Columns().AdjustToContents();

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

            // Title
            worksheet.Cell(1, 1).Value = "BÁO CÁO CHẤM CÔNG CÁ NHÂN";
            worksheet.Range(1, 1, 1, 8).Merge();
            worksheet.Cell(1, 1).Style
                .Font.SetBold(true)
                .Font.SetFontSize(16)
                .Alignment.SetHorizontal(XLAlignmentHorizontalValues.Center);

            // Employee info
            worksheet.Cell(3, 1).Value = "Mã NV:";
            worksheet.Cell(3, 2).Value = report.EmployeeCode;
            worksheet.Cell(3, 3).Value = "Họ tên:";
            worksheet.Cell(3, 4).Value = report.EmployeeName;
            worksheet.Cell(4, 1).Value = "Phòng ban:";
            worksheet.Cell(4, 2).Value = report.DepartmentName;
            worksheet.Cell(4, 3).Value = "Chức vụ:";
            worksheet.Cell(4, 4).Value = report.Position;
            worksheet.Cell(5, 1).Value = "Từ ngày:";
            worksheet.Cell(5, 2).Value = report.StartDate.ToString("dd/MM/yyyy");
            worksheet.Cell(5, 3).Value = "Đến ngày:";
            worksheet.Cell(5, 4).Value = report.EndDate.ToString("dd/MM/yyyy");

            // Summary
            worksheet.Cell(7, 1).Value = "TỔNG KẾT";
            worksheet.Cell(7, 1).Style.Font.SetBold(true);
            worksheet.Cell(8, 1).Value = $"Ngày có mặt: {report.TotalPresentDays} | Đi muộn: {report.TotalLateDays} | Về sớm: {report.TotalEarlyLeaveDays} | Nghỉ phép: {report.TotalLeaveDays} | Vắng: {report.TotalAbsentDays}";
            worksheet.Range(8, 1, 8, 8).Merge();
            worksheet.Cell(9, 1).Value = $"Tổng giờ làm: {report.TotalWorkedHours:F1}h | Tỷ lệ chấm công: {report.AttendanceRate:F1}%";
            worksheet.Range(9, 1, 9, 8).Merge();

            // Headers
            var headerRow = 11;
            var headers = new[] { "Ngày", "Thứ", "Giờ vào", "Giờ ra", "Giờ làm (phút)", "Muộn", "Về sớm", "Trạng thái" };
            for (int i = 0; i < headers.Length; i++)
            {
                worksheet.Cell(headerRow, i + 1).Value = headers[i];
            }
            worksheet.Range(headerRow, 1, headerRow, headers.Length).Style
                .Font.SetBold(true)
                .Fill.SetBackgroundColor(XLColor.LightBlue)
                .Border.SetOutsideBorder(XLBorderStyleValues.Thin);

            // Data
            var row = headerRow + 1;
            foreach (var item in report.DailyRecords)
            {
                worksheet.Cell(row, 1).Value = item.Date.ToString("dd/MM");
                worksheet.Cell(row, 2).Value = item.DayOfWeek;
                worksheet.Cell(row, 3).Value = item.CheckInTime?.ToString("HH:mm") ?? "-";
                worksheet.Cell(row, 4).Value = item.CheckOutTime?.ToString("HH:mm") ?? "-";
                worksheet.Cell(row, 5).Value = item.WorkedMinutes;
                worksheet.Cell(row, 6).Value = item.IsLate ? "✓" : "";
                worksheet.Cell(row, 7).Value = item.IsEarlyLeave ? "✓" : "";
                worksheet.Cell(row, 8).Value = item.Status;

                // Color coding
                if (item.IsHoliday || item.Date.DayOfWeek == DayOfWeek.Saturday || item.Date.DayOfWeek == DayOfWeek.Sunday)
                {
                    worksheet.Range(row, 1, row, 8).Style.Fill.SetBackgroundColor(XLColor.LightGray);
                }
                else if (item.Status == "Vắng mặt")
                {
                    worksheet.Range(row, 1, row, 8).Style.Fill.SetBackgroundColor(XLColor.LightPink);
                }
                else if (item.IsOnLeave)
                {
                    worksheet.Range(row, 1, row, 8).Style.Fill.SetBackgroundColor(XLColor.LightYellow);
                }

                row++;
            }

            // Auto-fit columns
            worksheet.Columns().AdjustToContents();

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
    public async Task<IActionResult> ExportLateEarlyReportExcel(
        [FromQuery] DateTime? startDate = null,
        [FromQuery] DateTime? endDate = null)
    {
        try
        {
            var reportResult = await GetLateEarlyReport(startDate, endDate);
            if (reportResult.Result is not OkObjectResult okResult 
                || okResult.Value is not AppResponse<LateEarlyReportDto> response 
                || response.Data == null)
            {
                return BadRequest("Failed to generate report");
            }

            var report = response.Data;

            using var workbook = new XLWorkbook();
            var worksheet = workbook.Worksheets.Add("Báo cáo đi muộn về sớm");

            // Title
            worksheet.Cell(1, 1).Value = "BÁO CÁO ĐI MUỘN - VỀ SỚM";
            worksheet.Range(1, 1, 1, 8).Merge();
            worksheet.Cell(1, 1).Style
                .Font.SetBold(true)
                .Font.SetFontSize(16)
                .Alignment.SetHorizontal(XLAlignmentHorizontalValues.Center);

            worksheet.Cell(2, 1).Value = $"Từ {report.StartDate:dd/MM/yyyy} đến {report.EndDate:dd/MM/yyyy}";
            worksheet.Range(2, 1, 2, 8).Merge();
            worksheet.Cell(2, 1).Style.Alignment.SetHorizontal(XLAlignmentHorizontalValues.Center);

            // Summary
            worksheet.Cell(4, 1).Value = $"Tổng NV: {report.TotalEmployees} | Vi phạm: {report.EmployeesWithIssues} | Lần muộn: {report.TotalLateCount} ({report.TotalLateMinutes} phút) | Về sớm: {report.TotalEarlyLeaveCount} ({report.TotalEarlyMinutes} phút)";
            worksheet.Range(4, 1, 4, 8).Merge();

            // Headers
            var headerRow = 6;
            var headers = new[] { "STT", "Mã NV", "Họ tên", "Phòng ban", "Lần muộn", "Phút muộn", "Lần về sớm", "Phút về sớm" };
            for (int i = 0; i < headers.Length; i++)
            {
                worksheet.Cell(headerRow, i + 1).Value = headers[i];
            }
            worksheet.Range(headerRow, 1, headerRow, headers.Length).Style
                .Font.SetBold(true)
                .Fill.SetBackgroundColor(XLColor.LightSalmon)
                .Border.SetOutsideBorder(XLBorderStyleValues.Thin);

            // Data
            var row = headerRow + 1;
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
            worksheet.Columns().AdjustToContents();

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

            // Title
            worksheet.Cell(1, 1).Value = "BÁO CÁO TỔNG HỢP THEO PHÒNG BAN";
            worksheet.Range(1, 1, 1, 7).Merge();
            worksheet.Cell(1, 1).Style
                .Font.SetBold(true)
                .Font.SetFontSize(16)
                .Alignment.SetHorizontal(XLAlignmentHorizontalValues.Center);

            worksheet.Cell(2, 1).Value = $"Tháng {report.Month}/{report.Year}";
            worksheet.Range(2, 1, 2, 7).Merge();
            worksheet.Cell(2, 1).Style.Alignment.SetHorizontal(XLAlignmentHorizontalValues.Center);

            // Headers
            var headerRow = 4;
            var headers = new[] { "STT", "Phòng ban", "Số NV", "Tổng chấm công", "Số lần muộn", "Tổng giờ làm", "Tỷ lệ CC (%)" };
            for (int i = 0; i < headers.Length; i++)
            {
                worksheet.Cell(headerRow, i + 1).Value = headers[i];
            }
            worksheet.Range(headerRow, 1, headerRow, headers.Length).Style
                .Font.SetBold(true)
                .Fill.SetBackgroundColor(XLColor.LightGreen)
                .Border.SetOutsideBorder(XLBorderStyleValues.Thin);

            // Data
            var row = headerRow + 1;
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
            worksheet.Columns().AdjustToContents();

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

            worksheet.Cell(1, 1).Value = "BÁO CÁO TĂNG CA";
            worksheet.Range(1, 1, 1, 7).Merge();
            worksheet.Cell(1, 1).Style
                .Font.SetBold(true)
                .Font.SetFontSize(16)
                .Alignment.SetHorizontal(XLAlignmentHorizontalValues.Center);

            worksheet.Cell(2, 1).Value = $"Từ {report.StartDate:dd/MM/yyyy} đến {report.EndDate:dd/MM/yyyy}";
            worksheet.Range(2, 1, 2, 7).Merge();
            worksheet.Cell(2, 1).Style.Alignment.SetHorizontal(XLAlignmentHorizontalValues.Center);

            worksheet.Cell(4, 1).Value = $"Tổng NV: {report.TotalEmployees} | NV tăng ca: {report.EmployeesWithOvertime} | Tổng giờ: {report.TotalOvertimeHours:F1}h";
            worksheet.Range(4, 1, 4, 7).Merge();

            var headerRow = 6;
            var headers = new[] { "STT", "Mã NV", "Họ tên", "Phòng ban", "Số ngày tăng ca", "Tổng phút tăng ca", "Tổng giờ tăng ca" };
            for (int i = 0; i < headers.Length; i++)
            {
                worksheet.Cell(headerRow, i + 1).Value = headers[i];
            }
            worksheet.Range(headerRow, 1, headerRow, headers.Length).Style
                .Font.SetBold(true)
                .Fill.SetBackgroundColor(XLColor.LightCoral)
                .Border.SetOutsideBorder(XLBorderStyleValues.Thin);

            var row = headerRow + 1;
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

            worksheet.Columns().AdjustToContents();

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

            worksheet.Cell(1, 1).Value = "BÁO CÁO NGHỈ PHÉP";
            worksheet.Range(1, 1, 1, 9).Merge();
            worksheet.Cell(1, 1).Style
                .Font.SetBold(true)
                .Font.SetFontSize(16)
                .Alignment.SetHorizontal(XLAlignmentHorizontalValues.Center);

            worksheet.Cell(2, 1).Value = $"Từ {report.StartDate:dd/MM/yyyy} đến {report.EndDate:dd/MM/yyyy}";
            worksheet.Range(2, 1, 2, 9).Merge();
            worksheet.Cell(2, 1).Style.Alignment.SetHorizontal(XLAlignmentHorizontalValues.Center);

            worksheet.Cell(4, 1).Value = $"Tổng NV: {report.TotalEmployees} | NV nghỉ: {report.EmployeesWithLeave} | Tổng đơn: {report.TotalLeaveRequests} | Đã duyệt: {report.ApprovedCount} | Từ chối: {report.RejectedCount}";
            worksheet.Range(4, 1, 4, 9).Merge();

            var headerRow = 6;
            var headers = new[] { "STT", "Mã NV", "Họ tên", "Phòng ban", "Loại nghỉ", "Tổng đơn", "Ngày nghỉ", "Đã dùng", "Còn lại" };
            for (int i = 0; i < headers.Length; i++)
            {
                worksheet.Cell(headerRow, i + 1).Value = headers[i];
            }
            worksheet.Range(headerRow, 1, headerRow, headers.Length).Style
                .Font.SetBold(true)
                .Fill.SetBackgroundColor(XLColor.LightBlue)
                .Border.SetOutsideBorder(XLBorderStyleValues.Thin);

            var row = headerRow + 1;
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

            worksheet.Columns().AdjustToContents();

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
    public List<MonthlyAttendanceItemDto> Items { get; set; } = new();
}

public class MonthlyAttendanceItemDto
{
    public Guid EmployeeId { get; set; }
    public string EmployeeCode { get; set; } = string.Empty;
    public string EmployeeName { get; set; } = string.Empty;
    public string DepartmentName { get; set; } = string.Empty;
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

using ClosedXML.Excel;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers.Reports;

/// <summary>
/// Cluster 1 — Chấm công chuyên sâu: compliance %, vắng không phép, no-show,
/// bất thường, công tác (field check-in) & mobile/WiFi attendance.
/// Tất cả endpoint hỗ trợ filter store/department/date và export Excel qua ?format=excel.
/// </summary>
[ApiController]
[Route("api/reports/attendance-analytics")]
[Authorize]
public class AttendanceAnalyticsController(
    ZKTecoDbContext db,
    ILogger<AttendanceAnalyticsController> logger
) : AuthenticatedControllerBase
{
    // ═════════════════════════════════════════════════════════════════════
    // 1. COMPLIANCE — Tỷ lệ chuyên cần theo nhân viên/tháng
    // GET /api/reports/attendance-analytics/compliance?year=&month=&department=&employeeCode=&format=
    // ═════════════════════════════════════════════════════════════════════
    [HttpGet("compliance")]
    [RequireModulePermission("AttendanceReport", ModulePermissionAction.View)]
    public async Task<IActionResult> GetCompliance(
        [FromQuery] int? year = null,
        [FromQuery] int? month = null,
        [FromQuery] string? department = null,
        [FromQuery] string? employeeCode = null,
        [FromQuery] string? format = null,
        CancellationToken ct = default)
    {
        try
        {
            var now = ReportHelpers.NowVn();
            var y = year ?? now.Year;
            var m = month ?? now.Month;
            var (startLocal, endLocal, utcStart, utcEnd) = ReportHelpers.VnMonthRange(y, m);
            var storeId = RequiredStoreId;

            var empQ = db.Employees.Where(e => e.StoreId == storeId && e.Deleted == null);
            if (!string.IsNullOrWhiteSpace(department))
                empQ = empQ.Where(e => e.Department != null && e.Department.Contains(department));
            if (!string.IsNullOrWhiteSpace(employeeCode))
                empQ = empQ.Where(e => e.EmployeeCode.Contains(employeeCode));

            var employees = await empQ
                .Select(e => new { e.Id, e.EmployeeCode, e.FirstName, e.LastName, e.Department, e.JoinDate, e.ResignationDate })
                .ToListAsync(ct);

            var pins = employees.Select(e => e.EmployeeCode).ToList();

            var rawAtt = await db.AttendanceLogs
                .Where(a => a.Device != null && a.Device.StoreId == storeId
                    && a.AttendanceTime >= utcStart && a.AttendanceTime < utcEnd
                    && pins.Contains(a.PIN))
                .Select(a => new { a.PIN, a.AttendanceTime, a.AttendanceState })
                .ToListAsync(ct);

            var attByPin = rawAtt
                .Select(a => new { a.PIN, VnDate = ReportHelpers.ToVn(a.AttendanceTime).Date, a.AttendanceState })
                .ToLookup(a => a.PIN);

            // Mobile punches as fallback (face/GPS check-ins)
            var empCodeSet = pins.ToHashSet();
            var mobileAtt = await db.MobileAttendanceRecords
                .Where(m => m.StoreId == storeId && m.PunchTime >= utcStart && m.PunchTime < utcEnd)
                .Select(m => new { m.OdooEmployeeId, m.PunchTime })
                .ToListAsync(ct);
            var mobileByCode = mobileAtt
                .Where(m => empCodeSet.Contains(m.OdooEmployeeId))
                .Select(m => new { m.OdooEmployeeId, VnDate = ReportHelpers.ToVn(m.PunchTime).Date })
                .ToLookup(m => m.OdooEmployeeId);

            var holidays = (await db.Holidays
                .Where(h => h.StoreId == storeId && h.Date >= startLocal && h.Date <= endLocal)
                .Select(h => h.Date.Date).ToListAsync(ct)).ToHashSet();

            var standardDays = ReportHelpers.CountWorkingDays(startLocal, endLocal, holidays);

            var employeeIds = employees.Select(e => e.Id).ToList();
            var schedules = await db.WorkSchedules
                .Where(ws => ws.StoreId == storeId && ws.Deleted == null
                    && ws.Date >= startLocal && ws.Date <= endLocal
                    && employeeIds.Contains(ws.EmployeeUserId))
                .Select(ws => new { ws.EmployeeUserId, ws.Date, ws.IsDayOff })
                .ToListAsync(ct);
            var schedulesByEmp = schedules.ToLookup(s => s.EmployeeUserId);

            var empUserIds = await db.Employees
                .Where(e => employeeIds.Contains(e.Id) && e.ApplicationUserId != null)
                .Select(e => new { e.Id, UserId = e.ApplicationUserId!.Value })
                .ToListAsync(ct);
            var empToUser = empUserIds.ToDictionary(x => x.Id, x => x.UserId);

            var leaves = await db.Leaves
                .Where(l => l.StoreId == storeId && l.Status == LeaveStatus.Approved
                    && l.StartDate <= endLocal && l.EndDate >= startLocal)
                .Select(l => new { l.EmployeeUserId, l.StartDate, l.EndDate })
                .ToListAsync(ct);
            var leavesByUser = leaves.ToLookup(l => l.EmployeeUserId);

            var lateThreshold = new TimeSpan(8, 30, 0);

            // Precompute: earliest check-in per (PIN, date) in VN local → late detection.
            var earliestCheckInByPinDate = rawAtt
                .Where(a => a.AttendanceState == AttendanceStates.CheckIn)
                .Select(a => new { a.PIN, Vn = ReportHelpers.ToVn(a.AttendanceTime) })
                .GroupBy(a => new { a.PIN, Date = a.Vn.Date })
                .ToDictionary(g => g.Key, g => g.Min(x => x.Vn));

            var items = new List<ComplianceItemDto>();
            foreach (var e in employees)
            {
                var presentDates = attByPin[e.EmployeeCode].Select(a => a.VnDate)
                    .Concat(mobileByCode[e.EmployeeCode].Select(m => m.VnDate))
                    .Distinct().ToHashSet();

                var lateDays = earliestCheckInByPinDate
                    .Where(kv => kv.Key.PIN == e.EmployeeCode)
                    .Count(kv => kv.Value.TimeOfDay > lateThreshold);

                int leaveDays = 0;
                if (empToUser.TryGetValue(e.Id, out var uid))
                {
                    foreach (var lv in leavesByUser[uid])
                    {
                        var s = lv.StartDate.Date < startLocal ? startLocal : lv.StartDate.Date;
                        var t = lv.EndDate.Date > endLocal ? endLocal : lv.EndDate.Date;
                        for (var d = s; d <= t; d = d.AddDays(1))
                        {
                            if (d.DayOfWeek == DayOfWeek.Saturday || d.DayOfWeek == DayOfWeek.Sunday) continue;
                            if (holidays.Contains(d)) continue;
                            leaveDays++;
                        }
                    }
                }

                // Personal standard days adjusted for joinDate/resignationDate (pro-rated)
                var personalStart = e.JoinDate.HasValue && e.JoinDate.Value.Date > startLocal ? e.JoinDate.Value.Date : startLocal;
                var personalEnd = e.ResignationDate.HasValue && e.ResignationDate.Value.Date < endLocal ? e.ResignationDate.Value.Date : endLocal;
                var personalStd = personalStart <= personalEnd
                    ? ReportHelpers.CountWorkingDays(personalStart, personalEnd, holidays)
                    : 0;

                var presentCount = presentDates.Count(d => d >= personalStart && d <= personalEnd);
                var absentDays = Math.Max(0, personalStd - presentCount - leaveDays);
                var rate = personalStd > 0 ? Math.Round((double)presentCount / personalStd * 100, 2) : 0;

                items.Add(new ComplianceItemDto
                {
                    EmployeeId = e.Id,
                    EmployeeCode = e.EmployeeCode,
                    EmployeeName = ReportHelpers.FullName(e.LastName, e.FirstName),
                    Department = e.Department ?? "N/A",
                    StandardDays = personalStd,
                    PresentDays = presentCount,
                    LateDays = lateDays,
                    LeaveDays = leaveDays,
                    AbsentDays = absentDays,
                    ComplianceRate = rate
                });
            }

            var report = new ComplianceReportDto
            {
                Year = y,
                Month = m,
                StandardDays = standardDays,
                TotalEmployees = items.Count,
                AvgComplianceRate = items.Count > 0 ? Math.Round(items.Average(i => i.ComplianceRate), 2) : 0,
                Items = items.OrderBy(i => i.Department).ThenBy(i => i.EmployeeCode).ToList()
            };

            if (string.Equals(format, "excel", StringComparison.OrdinalIgnoreCase))
                return ExportComplianceExcel(report);

            return Ok(AppResponse<ComplianceReportDto>.Success(report));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Compliance report failed");
            return StatusCode(500, AppResponse<ComplianceReportDto>.Fail(ex.Message));
        }
    }

    private IActionResult ExportComplianceExcel(ComplianceReportDto r)
    {
        var headers = new[] { "STT", "Mã NV", "Họ tên", "Phòng ban", "Ngày công chuẩn", "Ngày làm", "Đi muộn", "Nghỉ phép", "Vắng", "Tỷ lệ %" };
        return ReportHelpers.ExcelFile(
            $"Compliance {r.Month:D2}-{r.Year}",
            headers,
            (ws, dataStartRow) => { int row = dataStartRow;
                int idx = 1;
                foreach (var i in r.Items)
                {
                    ws.Cell(row, 1).Value = idx++;
                    ws.Cell(row, 2).Value = i.EmployeeCode;
                    ws.Cell(row, 3).Value = i.EmployeeName;
                    ws.Cell(row, 4).Value = i.Department;
                    ws.Cell(row, 5).Value = i.StandardDays;
                    ws.Cell(row, 6).Value = i.PresentDays;
                    ws.Cell(row, 7).Value = i.LateDays;
                    ws.Cell(row, 8).Value = i.LeaveDays;
                    ws.Cell(row, 9).Value = i.AbsentDays;
                    ReportHelpers.PercentCell(ws.Cell(row, 10), i.ComplianceRate);
                    row++;
                }
            },
            $"attendance-compliance-{r.Year}-{r.Month:D2}.xlsx", user: User);
    }

    // ═════════════════════════════════════════════════════════════════════
    // 2. ABSENCE — Danh sách vắng không phép (ngày-theo-ngày)
    // GET /api/reports/attendance-analytics/absence?from=&to=&department=
    // ═════════════════════════════════════════════════════════════════════
    [HttpGet("absence")]
    [RequireModulePermission("AttendanceReport", ModulePermissionAction.View)]
    public async Task<IActionResult> GetAbsence(
        [FromQuery] DateTime? from = null,
        [FromQuery] DateTime? to = null,
        [FromQuery] string? department = null,
        [FromQuery] string? format = null,
        CancellationToken ct = default)
    {
        try
        {
            var (fromLocal, toLocal, utcStart, utcEnd) = ReportHelpers.VnRange(from, to);
            var storeId = RequiredStoreId;

            var empQ = db.Employees.Where(e => e.StoreId == storeId && e.Deleted == null
                && e.WorkStatus == EmployeeWorkStatus.Active);
            if (!string.IsNullOrWhiteSpace(department))
                empQ = empQ.Where(e => e.Department != null && e.Department.Contains(department));

            var employees = await empQ
                .Select(e => new { e.Id, e.EmployeeCode, e.FirstName, e.LastName, e.Department, e.ApplicationUserId, e.JoinDate })
                .ToListAsync(ct);

            var pins = employees.Select(e => e.EmployeeCode).ToList();
            var userIds = employees.Where(e => e.ApplicationUserId.HasValue)
                .Select(e => e.ApplicationUserId!.Value).ToList();

            var attDates = await db.AttendanceLogs
                .Where(a => a.Device != null && a.Device.StoreId == storeId
                    && a.AttendanceTime >= utcStart && a.AttendanceTime < utcEnd
                    && pins.Contains(a.PIN))
                .Select(a => new { a.PIN, a.AttendanceTime })
                .ToListAsync(ct);
            var attByPinDate = attDates.Select(a => new { a.PIN, Dt = ReportHelpers.ToVn(a.AttendanceTime).Date })
                .Distinct().ToHashSet();

            var mobileDates = await db.MobileAttendanceRecords
                .Where(m => m.StoreId == storeId
                    && m.PunchTime >= utcStart && m.PunchTime < utcEnd
                    && pins.Contains(m.OdooEmployeeId))
                .Select(m => new { m.OdooEmployeeId, m.PunchTime })
                .ToListAsync(ct);
            var mobileByPinDate = mobileDates.Select(m => new { PIN = m.OdooEmployeeId, Dt = ReportHelpers.ToVn(m.PunchTime).Date })
                .Distinct().ToHashSet();

            var holidays = (await db.Holidays
                .Where(h => h.StoreId == storeId && h.Date >= fromLocal && h.Date <= toLocal)
                .Select(h => h.Date.Date).ToListAsync(ct)).ToHashSet();

            var leaves = await db.Leaves
                .Where(l => l.StoreId == storeId && l.Status == LeaveStatus.Approved
                    && l.StartDate <= toLocal && l.EndDate >= fromLocal
                    && userIds.Contains(l.EmployeeUserId))
                .Select(l => new { l.EmployeeUserId, l.StartDate, l.EndDate })
                .ToListAsync(ct);

            var leaveDatesByUser = new Dictionary<Guid, HashSet<DateTime>>();
            foreach (var lv in leaves)
            {
                if (!leaveDatesByUser.TryGetValue(lv.EmployeeUserId, out var set))
                {
                    set = new HashSet<DateTime>();
                    leaveDatesByUser[lv.EmployeeUserId] = set;
                }
                var s = lv.StartDate.Date < fromLocal ? fromLocal : lv.StartDate.Date;
                var t = lv.EndDate.Date > toLocal ? toLocal : lv.EndDate.Date;
                for (var d = s; d <= t; d = d.AddDays(1)) set.Add(d);
            }

            var items = new List<AbsenceItemDto>();
            foreach (var e in employees)
            {
                var personalStart = e.JoinDate.HasValue && e.JoinDate.Value.Date > fromLocal ? e.JoinDate.Value.Date : fromLocal;
                var leaveSet = e.ApplicationUserId.HasValue && leaveDatesByUser.TryGetValue(e.ApplicationUserId.Value, out var ls)
                    ? ls : new HashSet<DateTime>();

                for (var d = personalStart; d <= toLocal; d = d.AddDays(1))
                {
                    if (d.DayOfWeek == DayOfWeek.Saturday || d.DayOfWeek == DayOfWeek.Sunday) continue;
                    if (holidays.Contains(d)) continue;
                    if (leaveSet.Contains(d)) continue;
                    if (attByPinDate.Contains(new { PIN = e.EmployeeCode, Dt = d })) continue;
                    if (mobileByPinDate.Contains(new { PIN = e.EmployeeCode, Dt = d })) continue;

                    items.Add(new AbsenceItemDto
                    {
                        EmployeeId = e.Id,
                        EmployeeCode = e.EmployeeCode,
                        EmployeeName = ReportHelpers.FullName(e.LastName, e.FirstName),
                        Department = e.Department ?? "N/A",
                        AbsenceDate = d,
                        DayOfWeek = GetDowVn(d.DayOfWeek)
                    });
                }
            }

            var report = new AbsenceReportDto
            {
                From = fromLocal,
                To = toLocal,
                TotalAbsenceRecords = items.Count,
                AffectedEmployees = items.Select(i => i.EmployeeId).Distinct().Count(),
                Items = items.OrderBy(i => i.AbsenceDate).ThenBy(i => i.EmployeeCode).ToList()
            };

            if (string.Equals(format, "excel", StringComparison.OrdinalIgnoreCase))
            {
                return ReportHelpers.ExcelFile(
                    "Vắng không phép",
                    new[] { "STT", "Ngày", "Thứ", "Mã NV", "Họ tên", "Phòng ban" },
                    (ws, dataStartRow) => { int row = dataStartRow; int idx = 1;
                        foreach (var i in report.Items)
                        {
                            ws.Cell(row, 1).Value = idx++;
                            ReportHelpers.DateCell(ws.Cell(row, 2), i.AbsenceDate);
                            ws.Cell(row, 3).Value = i.DayOfWeek;
                            ws.Cell(row, 4).Value = i.EmployeeCode;
                            ws.Cell(row, 5).Value = i.EmployeeName;
                            ws.Cell(row, 6).Value = i.Department;
                            row++;
                        }
                    },
                    $"attendance-absence-{fromLocal:yyyyMMdd}-{toLocal:yyyyMMdd}.xlsx", user: User);
            }

            return Ok(AppResponse<AbsenceReportDto>.Success(report));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Absence report failed");
            return StatusCode(500, AppResponse<AbsenceReportDto>.Fail(ex.Message));
        }
    }

    // ═════════════════════════════════════════════════════════════════════
    // 3. NO-SHOW — Có WorkSchedule nhưng không có log chấm công
    // GET /api/reports/attendance-analytics/no-show?from=&to=&department=
    // ═════════════════════════════════════════════════════════════════════
    [HttpGet("no-show")]
    [RequireModulePermission("AttendanceReport", ModulePermissionAction.View)]
    public async Task<IActionResult> GetNoShow(
        [FromQuery] DateTime? from = null,
        [FromQuery] DateTime? to = null,
        [FromQuery] string? department = null,
        [FromQuery] string? format = null,
        CancellationToken ct = default)
    {
        try
        {
            var (fromLocal, toLocal, utcStart, utcEnd) = ReportHelpers.VnRange(from, to);
            var storeId = RequiredStoreId;

            var empQ = db.Employees.Where(e => e.StoreId == storeId && e.Deleted == null);
            if (!string.IsNullOrWhiteSpace(department))
                empQ = empQ.Where(e => e.Department != null && e.Department.Contains(department));

            var employees = await empQ
                .Select(e => new { e.Id, e.EmployeeCode, e.FirstName, e.LastName, e.Department, e.ApplicationUserId })
                .ToListAsync(ct);
            var empIds = employees.Select(e => e.Id).ToList();
            var empCodeByEmpId = employees.ToDictionary(e => e.Id, e => e.EmployeeCode);

            var schedules = await db.WorkSchedules
                .Where(ws => ws.StoreId == storeId && ws.Deleted == null
                    && ws.Date >= fromLocal && ws.Date <= toLocal && !ws.IsDayOff
                    && empIds.Contains(ws.EmployeeUserId))
                .Select(ws => new { ws.EmployeeUserId, ws.Date })
                .ToListAsync(ct);

            var pins = employees.Select(e => e.EmployeeCode).ToList();
            var userIds = employees.Where(e => e.ApplicationUserId.HasValue)
                .Select(e => e.ApplicationUserId!.Value).ToList();

            var attDates = (await db.AttendanceLogs
                .Where(a => a.Device != null && a.Device.StoreId == storeId
                    && a.AttendanceTime >= utcStart && a.AttendanceTime < utcEnd
                    && pins.Contains(a.PIN))
                .Select(a => new { a.PIN, a.AttendanceTime }).ToListAsync(ct))
                .Select(a => (Pin: a.PIN, Date: ReportHelpers.ToVn(a.AttendanceTime).Date))
                .Distinct().ToHashSet();

            var mobileDates = (await db.MobileAttendanceRecords
                .Where(m => m.StoreId == storeId && m.PunchTime >= utcStart && m.PunchTime < utcEnd
                    && pins.Contains(m.OdooEmployeeId))
                .Select(m => new { m.OdooEmployeeId, m.PunchTime }).ToListAsync(ct))
                .Select(m => (Pin: m.OdooEmployeeId, Date: ReportHelpers.ToVn(m.PunchTime).Date))
                .Distinct().ToHashSet();

            var leaves = await db.Leaves
                .Where(l => l.StoreId == storeId && l.Status == LeaveStatus.Approved
                    && l.StartDate <= toLocal && l.EndDate >= fromLocal
                    && userIds.Contains(l.EmployeeUserId))
                .Select(l => new { l.EmployeeUserId, l.StartDate, l.EndDate })
                .ToListAsync(ct);
            var leaveDatesByUser = BuildLeaveDateSet(leaves.Select(l => (l.EmployeeUserId, l.StartDate, l.EndDate)), fromLocal, toLocal);

            var items = new List<NoShowItemDto>();
            foreach (var s in schedules)
            {
                if (!empCodeByEmpId.TryGetValue(s.EmployeeUserId, out var code)) continue;
                var emp = employees.First(e => e.Id == s.EmployeeUserId);
                var date = s.Date.Date;

                if (attDates.Contains((code, date))) continue;
                if (mobileDates.Contains((code, date))) continue;
                if (emp.ApplicationUserId.HasValue
                    && leaveDatesByUser.TryGetValue(emp.ApplicationUserId.Value, out var set)
                    && set.Contains(date)) continue;

                items.Add(new NoShowItemDto
                {
                    EmployeeId = emp.Id,
                    EmployeeCode = code,
                    EmployeeName = ReportHelpers.FullName(emp.LastName, emp.FirstName),
                    Department = emp.Department ?? "N/A",
                    ScheduledDate = date,
                    DayOfWeek = GetDowVn(date.DayOfWeek)
                });
            }

            var report = new NoShowReportDto
            {
                From = fromLocal,
                To = toLocal,
                TotalNoShows = items.Count,
                Items = items.OrderBy(i => i.ScheduledDate).ThenBy(i => i.EmployeeCode).ToList()
            };

            if (string.Equals(format, "excel", StringComparison.OrdinalIgnoreCase))
            {
                return ReportHelpers.ExcelFile("No-show",
                    new[] { "STT", "Ngày xếp lịch", "Thứ", "Mã NV", "Họ tên", "Phòng ban" },
                    (ws, dataStartRow) => { int row = dataStartRow; int idx = 1;
                        foreach (var i in report.Items)
                        {
                            ws.Cell(row, 1).Value = idx++;
                            ReportHelpers.DateCell(ws.Cell(row, 2), i.ScheduledDate);
                            ws.Cell(row, 3).Value = i.DayOfWeek;
                            ws.Cell(row, 4).Value = i.EmployeeCode;
                            ws.Cell(row, 5).Value = i.EmployeeName;
                            ws.Cell(row, 6).Value = i.Department;
                            row++;
                        }
                    },
                    $"attendance-noshow-{fromLocal:yyyyMMdd}-{toLocal:yyyyMMdd}.xlsx", user: User);
            }

            return Ok(AppResponse<NoShowReportDto>.Success(report));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "No-show report failed");
            return StatusCode(500, AppResponse<NoShowReportDto>.Fail(ex.Message));
        }
    }

    // ═════════════════════════════════════════════════════════════════════
    // 4. ANOMALIES — Ra vào bất thường (quá sớm/quá muộn/nhiều lần)
    // GET /api/reports/attendance-analytics/anomalies?from=&to=&department=&minPunchesPerDay=&earlyMinutes=&lateMinutes=
    // ═════════════════════════════════════════════════════════════════════
    [HttpGet("anomalies")]
    [RequireModulePermission("AttendanceReport", ModulePermissionAction.View)]
    public async Task<IActionResult> GetAnomalies(
        [FromQuery] DateTime? from = null,
        [FromQuery] DateTime? to = null,
        [FromQuery] string? department = null,
        [FromQuery] int maxPunchesPerDay = 4,
        [FromQuery] int earlyArrivalMinutes = 60,
        [FromQuery] int lateDepartureMinutes = 60,
        [FromQuery] string? format = null,
        CancellationToken ct = default)
    {
        try
        {
            var (fromLocal, toLocal, utcStart, utcEnd) = ReportHelpers.VnRange(from, to);
            var storeId = RequiredStoreId;

            var empQ = db.Employees.Where(e => e.StoreId == storeId && e.Deleted == null);
            if (!string.IsNullOrWhiteSpace(department))
                empQ = empQ.Where(e => e.Department != null && e.Department.Contains(department));

            var employees = await empQ
                .Select(e => new { e.Id, e.EmployeeCode, e.FirstName, e.LastName, e.Department })
                .ToListAsync(ct);
            var pins = employees.Select(e => e.EmployeeCode).ToHashSet();

            var raw = await db.AttendanceLogs
                .Where(a => a.Device != null && a.Device.StoreId == storeId
                    && a.AttendanceTime >= utcStart && a.AttendanceTime < utcEnd
                    && pins.Contains(a.PIN))
                .Select(a => new { a.PIN, a.AttendanceTime, a.AttendanceState })
                .ToListAsync(ct);

            var vnPunches = raw.Select(a => new { a.PIN, Vn = ReportHelpers.ToVn(a.AttendanceTime), a.AttendanceState }).ToList();
            var byEmpDay = vnPunches.GroupBy(p => new { p.PIN, Date = p.Vn.Date });

            var items = new List<AnomalyItemDto>();
            var standardStart = new TimeSpan(8, 30, 0);
            var standardEnd = new TimeSpan(18, 0, 0);

            foreach (var g in byEmpDay)
            {
                var emp = employees.FirstOrDefault(e => e.EmployeeCode == g.Key.PIN);
                if (emp == null) continue;
                var list = g.OrderBy(p => p.Vn).ToList();
                var first = list.First().Vn;
                var last = list.Last().Vn;
                var issues = new List<string>();

                if (list.Count > maxPunchesPerDay)
                    issues.Add($"Chấm công {list.Count} lần (quá {maxPunchesPerDay})");

                var firstTime = first.TimeOfDay;
                if (firstTime < standardStart && (standardStart - firstTime).TotalMinutes >= earlyArrivalMinutes)
                    issues.Add($"Đến sớm bất thường {(int)(standardStart - firstTime).TotalMinutes} phút");

                var lastTime = last.TimeOfDay;
                if (lastTime > standardEnd && (lastTime - standardEnd).TotalMinutes >= lateDepartureMinutes)
                    issues.Add($"Ra về muộn bất thường {(int)(lastTime - standardEnd).TotalMinutes} phút");

                if (issues.Count == 0) continue;

                items.Add(new AnomalyItemDto
                {
                    EmployeeId = emp.Id,
                    EmployeeCode = emp.EmployeeCode,
                    EmployeeName = ReportHelpers.FullName(emp.LastName, emp.FirstName),
                    Department = emp.Department ?? "N/A",
                    Date = g.Key.Date,
                    FirstPunch = first,
                    LastPunch = last,
                    PunchCount = list.Count,
                    Issues = string.Join("; ", issues)
                });
            }

            var report = new AnomalyReportDto
            {
                From = fromLocal,
                To = toLocal,
                Total = items.Count,
                Items = items.OrderBy(i => i.Date).ThenBy(i => i.EmployeeCode).ToList()
            };

            if (string.Equals(format, "excel", StringComparison.OrdinalIgnoreCase))
            {
                return ReportHelpers.ExcelFile("Anomalies",
                    new[] { "STT", "Ngày", "Mã NV", "Họ tên", "Phòng ban", "Vào đầu", "Ra cuối", "Số lần", "Bất thường" },
                    (ws, dataStartRow) => { int row = dataStartRow; int idx = 1;
                        foreach (var i in report.Items)
                        {
                            ws.Cell(row, 1).Value = idx++;
                            ReportHelpers.DateCell(ws.Cell(row, 2), i.Date);
                            ws.Cell(row, 3).Value = i.EmployeeCode;
                            ws.Cell(row, 4).Value = i.EmployeeName;
                            ws.Cell(row, 5).Value = i.Department;
                            ws.Cell(row, 6).Value = i.FirstPunch.ToString("HH:mm");
                            ws.Cell(row, 7).Value = i.LastPunch.ToString("HH:mm");
                            ws.Cell(row, 8).Value = i.PunchCount;
                            ws.Cell(row, 9).Value = i.Issues;
                            row++;
                        }
                    },
                    $"attendance-anomalies-{fromLocal:yyyyMMdd}-{toLocal:yyyyMMdd}.xlsx", user: User);
            }

            return Ok(AppResponse<AnomalyReportDto>.Success(report));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Anomaly report failed");
            return StatusCode(500, AppResponse<AnomalyReportDto>.Fail(ex.Message));
        }
    }

    // ═════════════════════════════════════════════════════════════════════
    // 5. FIELD SUMMARY — Tổng hợp VisitReport (công tác / check-in điểm bán)
    // GET /api/reports/attendance-analytics/field-summary?from=&to=&employeeCode=
    // ═════════════════════════════════════════════════════════════════════
    [HttpGet("field-summary")]
    [RequireModulePermission("AttendanceReport", ModulePermissionAction.View)]
    public async Task<IActionResult> GetFieldSummary(
        [FromQuery] DateTime? from = null,
        [FromQuery] DateTime? to = null,
        [FromQuery] string? employeeCode = null,
        [FromQuery] string? format = null,
        CancellationToken ct = default)
    {
        try
        {
            var (fromLocal, toLocal, _, _) = ReportHelpers.VnRange(from, to);
            var storeId = RequiredStoreId;

            var q = db.VisitReports
                .Where(v => v.StoreId == storeId && v.VisitDate >= fromLocal && v.VisitDate <= toLocal);
            if (!string.IsNullOrWhiteSpace(employeeCode))
                q = q.Where(v => v.EmployeeId == employeeCode);

            var raw = await q
                .Select(v => new { v.EmployeeId, v.EmployeeName, v.LocationName, v.VisitDate, v.CheckInTime, v.CheckOutTime, v.TimeSpentMinutes })
                .ToListAsync(ct);

            var items = raw
                .GroupBy(v => new { v.EmployeeId, v.EmployeeName })
                .Select(g => new FieldSummaryItemDto
                {
                    EmployeeCode = g.Key.EmployeeId,
                    EmployeeName = g.Key.EmployeeName,
                    TotalVisits = g.Count(),
                    DistinctLocations = g.Select(x => x.LocationName).Distinct().Count(),
                    TotalMinutes = g.Sum(x => x.TimeSpentMinutes ?? 0),
                    FirstVisit = g.Min(x => x.VisitDate),
                    LastVisit = g.Max(x => x.VisitDate)
                })
                .OrderByDescending(i => i.TotalVisits)
                .ToList();

            var report = new FieldSummaryReportDto
            {
                From = fromLocal, To = toLocal,
                TotalVisits = raw.Count,
                TotalEmployees = items.Count,
                Items = items
            };

            if (string.Equals(format, "excel", StringComparison.OrdinalIgnoreCase))
            {
                return ReportHelpers.ExcelFile("Field summary",
                    new[] { "STT", "Mã NV", "Họ tên", "Số lần thăm", "Điểm khác nhau", "Tổng phút", "Lần đầu", "Lần cuối" },
                    (ws, dataStartRow) => { int row = dataStartRow; int idx = 1;
                        foreach (var i in items)
                        {
                            ws.Cell(row, 1).Value = idx++;
                            ws.Cell(row, 2).Value = i.EmployeeCode;
                            ws.Cell(row, 3).Value = i.EmployeeName;
                            ws.Cell(row, 4).Value = i.TotalVisits;
                            ws.Cell(row, 5).Value = i.DistinctLocations;
                            ws.Cell(row, 6).Value = i.TotalMinutes;
                            ReportHelpers.DateCell(ws.Cell(row, 7), i.FirstVisit);
                            ReportHelpers.DateCell(ws.Cell(row, 8), i.LastVisit);
                            row++;
                        }
                    },
                    $"field-summary-{fromLocal:yyyyMMdd}-{toLocal:yyyyMMdd}.xlsx", user: User);
            }

            return Ok(AppResponse<FieldSummaryReportDto>.Success(report));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Field summary failed");
            return StatusCode(500, AppResponse<FieldSummaryReportDto>.Fail(ex.Message));
        }
    }

    // ═════════════════════════════════════════════════════════════════════
    // 6. MOBILE USAGE — Thống kê mức dùng Mobile/WiFi attendance
    // GET /api/reports/attendance-analytics/mobile-usage?from=&to=
    // ═════════════════════════════════════════════════════════════════════
    [HttpGet("mobile-usage")]
    [RequireModulePermission("AttendanceReport", ModulePermissionAction.View)]
    public async Task<IActionResult> GetMobileUsage(
        [FromQuery] DateTime? from = null,
        [FromQuery] DateTime? to = null,
        [FromQuery] string? format = null,
        CancellationToken ct = default)
    {
        try
        {
            var (fromLocal, toLocal, utcStart, utcEnd) = ReportHelpers.VnRange(from, to);
            var storeId = RequiredStoreId;

            var raw = await db.MobileAttendanceRecords
                .Where(m => m.StoreId == storeId && m.PunchTime >= utcStart && m.PunchTime < utcEnd)
                .Select(m => new { m.OdooEmployeeId, m.EmployeeName, m.PunchType, m.PunchTime, m.VerifyMethod, m.Status, m.DeviceId, m.WifiSsid })
                .ToListAsync(ct);

            var items = raw
                .GroupBy(r => new { r.OdooEmployeeId, r.EmployeeName })
                .Select(g => new MobileUsageItemDto
                {
                    EmployeeCode = g.Key.OdooEmployeeId,
                    EmployeeName = g.Key.EmployeeName,
                    TotalPunches = g.Count(),
                    CheckIns = g.Count(x => x.PunchType == 0),
                    CheckOuts = g.Count(x => x.PunchType == 1),
                    FaceGpsCount = g.Count(x => x.VerifyMethod == "face_gps" || x.VerifyMethod == "face"),
                    WifiCount = g.Count(x => !string.IsNullOrEmpty(x.WifiSsid)),
                    PendingCount = g.Count(x => x.Status == "pending"),
                    RejectedCount = g.Count(x => x.Status == "rejected"),
                    DevicesUsed = g.Select(x => x.DeviceId).Where(d => !string.IsNullOrEmpty(d)).Distinct().Count()
                })
                .OrderByDescending(i => i.TotalPunches)
                .ToList();

            var report = new MobileUsageReportDto
            {
                From = fromLocal, To = toLocal,
                TotalPunches = raw.Count,
                TotalEmployees = items.Count,
                Items = items
            };

            if (string.Equals(format, "excel", StringComparison.OrdinalIgnoreCase))
            {
                return ReportHelpers.ExcelFile("Mobile usage",
                    new[] { "STT", "Mã NV", "Họ tên", "Tổng lần", "Check-in", "Check-out", "Face/GPS", "WiFi", "Chờ duyệt", "Từ chối", "Số thiết bị" },
                    (ws, dataStartRow) => { int row = dataStartRow; int idx = 1;
                        foreach (var i in items)
                        {
                            ws.Cell(row, 1).Value = idx++;
                            ws.Cell(row, 2).Value = i.EmployeeCode;
                            ws.Cell(row, 3).Value = i.EmployeeName;
                            ws.Cell(row, 4).Value = i.TotalPunches;
                            ws.Cell(row, 5).Value = i.CheckIns;
                            ws.Cell(row, 6).Value = i.CheckOuts;
                            ws.Cell(row, 7).Value = i.FaceGpsCount;
                            ws.Cell(row, 8).Value = i.WifiCount;
                            ws.Cell(row, 9).Value = i.PendingCount;
                            ws.Cell(row, 10).Value = i.RejectedCount;
                            ws.Cell(row, 11).Value = i.DevicesUsed;
                            row++;
                        }
                    },
                    $"mobile-usage-{fromLocal:yyyyMMdd}-{toLocal:yyyyMMdd}.xlsx", user: User);
            }

            return Ok(AppResponse<MobileUsageReportDto>.Success(report));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Mobile usage report failed");
            return StatusCode(500, AppResponse<MobileUsageReportDto>.Fail(ex.Message));
        }
    }

    // ── Helpers ────────────────────────────────────────────────────────────
    private static string GetDowVn(DayOfWeek d) => d switch
    {
        DayOfWeek.Monday => "Thứ 2",
        DayOfWeek.Tuesday => "Thứ 3",
        DayOfWeek.Wednesday => "Thứ 4",
        DayOfWeek.Thursday => "Thứ 5",
        DayOfWeek.Friday => "Thứ 6",
        DayOfWeek.Saturday => "Thứ 7",
        _ => "CN"
    };

    private static Dictionary<Guid, HashSet<DateTime>> BuildLeaveDateSet(
        IEnumerable<(Guid UserId, DateTime StartDate, DateTime EndDate)> leaves,
        DateTime rangeFrom, DateTime rangeTo)
    {
        var map = new Dictionary<Guid, HashSet<DateTime>>();
        foreach (var lv in leaves)
        {
            if (!map.TryGetValue(lv.UserId, out var set)) map[lv.UserId] = set = new HashSet<DateTime>();
            var s = lv.StartDate.Date < rangeFrom ? rangeFrom : lv.StartDate.Date;
            var t = lv.EndDate.Date > rangeTo ? rangeTo : lv.EndDate.Date;
            for (var d = s; d <= t; d = d.AddDays(1)) set.Add(d);
        }
        return map;
    }
}

// ═════════════════════════════════════════════════════════════════════════
// DTOs (Cluster 1)
// ═════════════════════════════════════════════════════════════════════════

public class ComplianceReportDto
{
    public int Year { get; set; }
    public int Month { get; set; }
    public int StandardDays { get; set; }
    public int TotalEmployees { get; set; }
    public double AvgComplianceRate { get; set; }
    public List<ComplianceItemDto> Items { get; set; } = new();
}
public class ComplianceItemDto
{
    public Guid EmployeeId { get; set; }
    public string EmployeeCode { get; set; } = string.Empty;
    public string EmployeeName { get; set; } = string.Empty;
    public string Department { get; set; } = string.Empty;
    public int StandardDays { get; set; }
    public int PresentDays { get; set; }
    public int LateDays { get; set; }
    public int LeaveDays { get; set; }
    public int AbsentDays { get; set; }
    public double ComplianceRate { get; set; }
}

public class AbsenceReportDto
{
    public DateTime From { get; set; }
    public DateTime To { get; set; }
    public int TotalAbsenceRecords { get; set; }
    public int AffectedEmployees { get; set; }
    public List<AbsenceItemDto> Items { get; set; } = new();
}
public class AbsenceItemDto
{
    public Guid EmployeeId { get; set; }
    public string EmployeeCode { get; set; } = string.Empty;
    public string EmployeeName { get; set; } = string.Empty;
    public string Department { get; set; } = string.Empty;
    public DateTime AbsenceDate { get; set; }
    public string DayOfWeek { get; set; } = string.Empty;
}

public class NoShowReportDto
{
    public DateTime From { get; set; }
    public DateTime To { get; set; }
    public int TotalNoShows { get; set; }
    public List<NoShowItemDto> Items { get; set; } = new();
}
public class NoShowItemDto
{
    public Guid EmployeeId { get; set; }
    public string EmployeeCode { get; set; } = string.Empty;
    public string EmployeeName { get; set; } = string.Empty;
    public string Department { get; set; } = string.Empty;
    public DateTime ScheduledDate { get; set; }
    public string DayOfWeek { get; set; } = string.Empty;
}

public class AnomalyReportDto
{
    public DateTime From { get; set; }
    public DateTime To { get; set; }
    public int Total { get; set; }
    public List<AnomalyItemDto> Items { get; set; } = new();
}
public class AnomalyItemDto
{
    public Guid EmployeeId { get; set; }
    public string EmployeeCode { get; set; } = string.Empty;
    public string EmployeeName { get; set; } = string.Empty;
    public string Department { get; set; } = string.Empty;
    public DateTime Date { get; set; }
    public DateTime FirstPunch { get; set; }
    public DateTime LastPunch { get; set; }
    public int PunchCount { get; set; }
    public string Issues { get; set; } = string.Empty;
}

public class FieldSummaryReportDto
{
    public DateTime From { get; set; }
    public DateTime To { get; set; }
    public int TotalVisits { get; set; }
    public int TotalEmployees { get; set; }
    public List<FieldSummaryItemDto> Items { get; set; } = new();
}
public class FieldSummaryItemDto
{
    public string EmployeeCode { get; set; } = string.Empty;
    public string EmployeeName { get; set; } = string.Empty;
    public int TotalVisits { get; set; }
    public int DistinctLocations { get; set; }
    public int TotalMinutes { get; set; }
    public DateTime FirstVisit { get; set; }
    public DateTime LastVisit { get; set; }
}

public class MobileUsageReportDto
{
    public DateTime From { get; set; }
    public DateTime To { get; set; }
    public int TotalPunches { get; set; }
    public int TotalEmployees { get; set; }
    public List<MobileUsageItemDto> Items { get; set; } = new();
}
public class MobileUsageItemDto
{
    public string EmployeeCode { get; set; } = string.Empty;
    public string EmployeeName { get; set; } = string.Empty;
    public int TotalPunches { get; set; }
    public int CheckIns { get; set; }
    public int CheckOuts { get; set; }
    public int FaceGpsCount { get; set; }
    public int WifiCount { get; set; }
    public int PendingCount { get; set; }
    public int RejectedCount { get; set; }
    public int DevicesUsed { get; set; }
}


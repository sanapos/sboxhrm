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
/// Cluster 2 — Nghỉ phép & ca kíp: số dư phép, SLA duyệt đơn, quota ca, đổi ca.
/// </summary>
[ApiController]
[Route("api/reports/leave-shift")]
[Authorize]
public class LeaveShiftReportsController(
    ZKTecoDbContext db,
    ILogger<LeaveShiftReportsController> logger
) : AuthenticatedControllerBase
{
    // ═════════════════════════════════════════════════════════════════════
    // 1. LEAVE BALANCE — Số dư phép theo nhân viên/năm
    // GET /api/reports/leave-shift/leave-balance?year=&department=&format=
    // ═════════════════════════════════════════════════════════════════════
    [HttpGet("leave-balance")]
    [RequireModulePermission("LeaveReport", ModulePermissionAction.View)]
    public async Task<IActionResult> GetLeaveBalance(
        [FromQuery] int? year = null,
        [FromQuery] string? department = null,
        [FromQuery] string? format = null,
        CancellationToken ct = default)
    {
        try
        {
            var y = year ?? ReportHelpers.NowVn().Year;
            var storeId = RequiredStoreId;
            var yearStart = new DateTime(y, 1, 1);
            var yearEnd = new DateTime(y, 12, 31);

            var empQ = db.Employees.Where(e => e.StoreId == storeId && e.Deleted == null);
            if (!string.IsNullOrWhiteSpace(department))
                empQ = empQ.Where(e => e.Department != null && e.Department.Contains(department));

            var employees = await empQ
                .Select(e => new { e.Id, e.EmployeeCode, e.FirstName, e.LastName, e.Department, e.ApplicationUserId })
                .ToListAsync(ct);

            var empIds = employees.Select(e => e.Id).ToList();
            var userIds = employees.Where(e => e.ApplicationUserId.HasValue)
                .Select(e => e.ApplicationUserId!.Value).ToList();

            // Working info (entitlements)
            var workingInfos = await db.EmployeeWorkingInfos
                .Where(w => empIds.Contains(w.EmployeeId))
                .Select(w => new { w.EmployeeId, w.BalancedPaidLeaveDays, w.BalancedUnpaidLeaveDays, w.PaidLeaveDaysPerYear, w.UnpaidLeaveDaysPerYear })
                .ToListAsync(ct);
            var infoByEmp = workingInfos.ToDictionary(w => w.EmployeeId);

            // Approved leaves in the year
            var leaves = await db.Leaves
                .Where(l => l.StoreId == storeId && l.Status == LeaveStatus.Approved
                    && l.StartDate <= yearEnd && l.EndDate >= yearStart
                    && userIds.Contains(l.EmployeeUserId))
                .Select(l => new { l.EmployeeUserId, l.Type, l.StartDate, l.EndDate, l.IsHalfShift })
                .ToListAsync(ct);

            static double DaysIn(DateTime from, DateTime to, DateTime rStart, DateTime rEnd, bool half)
            {
                var s = from.Date < rStart ? rStart : from.Date;
                var t = to.Date > rEnd ? rEnd : to.Date;
                if (t < s) return 0;
                var days = (t - s).TotalDays + 1;
                return half ? days * 0.5 : days;
            }

            var items = new List<LeaveBalanceItemDto>();
            foreach (var e in employees)
            {
                infoByEmp.TryGetValue(e.Id, out var info);
                var entitlement = info?.PaidLeaveDaysPerYear ?? 12m;
                var balanceRemaining = info?.BalancedPaidLeaveDays ?? 0m;

                var empLeaves = e.ApplicationUserId.HasValue
                    ? leaves.Where(l => l.EmployeeUserId == e.ApplicationUserId.Value).ToList()
                    : new();

                double paidUsed = 0, unpaidUsed = 0, sickUsed = 0, otherUsed = 0;
                foreach (var lv in empLeaves)
                {
                    var d = DaysIn(lv.StartDate, lv.EndDate, yearStart, yearEnd, lv.IsHalfShift);
                    switch (lv.Type)
                    {
                        case LeaveType.AnnualLeave:
                        case LeaveType.PersonalPaid:
                        case LeaveType.CompensatoryLeave:
                            paidUsed += d; break;
                        case LeaveType.PersonalUnpaid:
                        case LeaveType.LongTermLeave:
                            unpaidUsed += d; break;
                        case LeaveType.SickLeave:
                        case LeaveType.MaternityLeave:
                            sickUsed += d; break;
                        default:
                            otherUsed += d; break;
                    }
                }

                items.Add(new LeaveBalanceItemDto
                {
                    EmployeeId = e.Id,
                    EmployeeCode = e.EmployeeCode,
                    EmployeeName = ReportHelpers.FullName(e.LastName, e.FirstName),
                    Department = e.Department ?? "N/A",
                    PaidEntitlement = entitlement,
                    PaidUsed = (decimal)paidUsed,
                    PaidRemaining = balanceRemaining,
                    UnpaidUsed = (decimal)unpaidUsed,
                    SickUsed = (decimal)sickUsed,
                    OtherUsed = (decimal)otherUsed,
                    UsagePercent = entitlement > 0 ? Math.Round((double)(paidUsed / (double)entitlement) * 100, 2) : 0
                });
            }

            var report = new LeaveBalanceReportDto
            {
                Year = y,
                TotalEmployees = items.Count,
                Items = items.OrderBy(i => i.Department).ThenBy(i => i.EmployeeCode).ToList()
            };

            if (string.Equals(format, "excel", StringComparison.OrdinalIgnoreCase))
            {
                return ReportHelpers.ExcelFile($"Leave balance {y}",
                    new[] { "STT", "Mã NV", "Họ tên", "Phòng ban", "Định mức", "Đã dùng (phép)", "Còn lại", "Không lương", "Nghỉ ốm", "Khác", "% dùng" },
                    (ws, dataStartRow) => { int row = dataStartRow; int idx = 1;
                        foreach (var i in report.Items)
                        {
                            ws.Cell(row, 1).Value = idx++;
                            ws.Cell(row, 2).Value = i.EmployeeCode;
                            ws.Cell(row, 3).Value = i.EmployeeName;
                            ws.Cell(row, 4).Value = i.Department;
                            ws.Cell(row, 5).Value = (double)i.PaidEntitlement;
                            ws.Cell(row, 6).Value = (double)i.PaidUsed;
                            ws.Cell(row, 7).Value = (double)i.PaidRemaining;
                            ws.Cell(row, 8).Value = (double)i.UnpaidUsed;
                            ws.Cell(row, 9).Value = (double)i.SickUsed;
                            ws.Cell(row, 10).Value = (double)i.OtherUsed;
                            ReportHelpers.PercentCell(ws.Cell(row, 11), i.UsagePercent);
                            row++;
                        }
                    },
                    $"leave-balance-{y}.xlsx", user: User);
            }

            return Ok(AppResponse<LeaveBalanceReportDto>.Success(report));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Leave balance failed");
            return StatusCode(500, AppResponse<LeaveBalanceReportDto>.Fail(ex.Message));
        }
    }

    // ═════════════════════════════════════════════════════════════════════
    // 2. LEAVE APPROVAL SLA — Thời gian duyệt + tỷ lệ duyệt/từ chối
    // GET /api/reports/leave-shift/leave-approval-sla?from=&to=
    // ═════════════════════════════════════════════════════════════════════
    [HttpGet("leave-approval-sla")]
    [RequireModulePermission("LeaveReport", ModulePermissionAction.View)]
    public async Task<IActionResult> GetLeaveApprovalSla(
        [FromQuery] DateTime? from = null,
        [FromQuery] DateTime? to = null,
        [FromQuery] string? format = null,
        CancellationToken ct = default)
    {
        try
        {
            var (fromLocal, toLocal, _, _) = ReportHelpers.VnRange(from, to);
            var storeId = RequiredStoreId;

            var leaves = await db.Leaves
                .Where(l => l.StoreId == storeId
                    && l.CreatedAt >= fromLocal && l.CreatedAt <= toLocal.AddDays(1))
                .Select(l => new { l.Id, l.EmployeeUserId, l.CreatedAt, l.Status, l.Type,
                    ApprovalDate = l.ApprovalRecords
                        .Where(r => r.Status != ApprovalStatus.Pending)
                        .OrderByDescending(r => r.ActionDate)
                        .Select(r => r.ActionDate).FirstOrDefault()
                })
                .ToListAsync(ct);

            var total = leaves.Count;
            var approved = leaves.Count(l => l.Status == LeaveStatus.Approved);
            var rejected = leaves.Count(l => l.Status == LeaveStatus.Rejected);
            var pending = leaves.Count(l => l.Status == LeaveStatus.Pending);
            var cancelled = leaves.Count(l => l.Status == LeaveStatus.Cancelled);

            var processed = leaves.Where(l => l.ApprovalDate.HasValue).ToList();
            var avgHours = processed.Count > 0
                ? processed.Average(l => (l.ApprovalDate!.Value - l.CreatedAt).TotalHours)
                : 0;

            // Per-approver SLA
            var records = await db.LeaveApprovalRecords
                .Where(r => r.StoreId == storeId && r.ActualUserId.HasValue && r.ActionDate.HasValue
                    && r.ActionDate >= fromLocal && r.ActionDate <= toLocal.AddDays(1))
                .Select(r => new { r.Leave!.CreatedAt, r.ActualUserId, r.ActualUserName, r.Status, r.ActionDate })
                .ToListAsync(ct);

            var perApprover = records
                .GroupBy(r => new { r.ActualUserId, r.ActualUserName })
                .Select(g => new LeaveApproverSlaDto
                {
                    ApproverId = g.Key.ActualUserId ?? Guid.Empty,
                    ApproverName = g.Key.ActualUserName ?? "-",
                    Total = g.Count(),
                    Approved = g.Count(x => x.Status == ApprovalStatus.Approved),
                    Rejected = g.Count(x => x.Status == ApprovalStatus.Rejected),
                    AvgResponseHours = g.Average(x => (x.ActionDate!.Value - x.CreatedAt).TotalHours)
                })
                .OrderByDescending(a => a.Total)
                .ToList();

            var report = new LeaveApprovalSlaReportDto
            {
                From = fromLocal, To = toLocal,
                TotalRequests = total,
                Approved = approved, Rejected = rejected, Pending = pending, Cancelled = cancelled,
                ApprovalRate = total > 0 ? Math.Round((double)approved / total * 100, 2) : 0,
                RejectionRate = total > 0 ? Math.Round((double)rejected / total * 100, 2) : 0,
                AvgResolutionHours = Math.Round(avgHours, 2),
                Approvers = perApprover
            };

            if (string.Equals(format, "excel", StringComparison.OrdinalIgnoreCase))
            {
                return ReportHelpers.ExcelFile("SLA duyệt phép",
                    new[] { "Người duyệt", "Tổng", "Duyệt", "Từ chối", "Trung bình (giờ)" },
                    (ws, dataStartRow) => { int row = dataStartRow;
                        foreach (var a in perApprover)
                        {
                            ws.Cell(row, 1).Value = a.ApproverName;
                            ws.Cell(row, 2).Value = a.Total;
                            ws.Cell(row, 3).Value = a.Approved;
                            ws.Cell(row, 4).Value = a.Rejected;
                            ws.Cell(row, 5).Value = Math.Round(a.AvgResponseHours, 2);
                            row++;
                        }
                    },
                    $"leave-approval-sla-{fromLocal:yyyyMMdd}-{toLocal:yyyyMMdd}.xlsx", user: User);
            }

            return Ok(AppResponse<LeaveApprovalSlaReportDto>.Success(report));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Leave approval SLA failed");
            return StatusCode(500, AppResponse<LeaveApprovalSlaReportDto>.Fail(ex.Message));
        }
    }

    // ═════════════════════════════════════════════════════════════════════
    // 3. SHIFT COVERAGE — So sánh quota vs đăng ký thực tế
    // GET /api/reports/leave-shift/shift-coverage?from=&to=&department=
    // ═════════════════════════════════════════════════════════════════════
    [HttpGet("shift-coverage")]
    [RequireModulePermission("LeaveReport", ModulePermissionAction.View)]
    public async Task<IActionResult> GetShiftCoverage(
        [FromQuery] DateTime? from = null,
        [FromQuery] DateTime? to = null,
        [FromQuery] string? department = null,
        [FromQuery] string? format = null,
        CancellationToken ct = default)
    {
        try
        {
            var (fromLocal, toLocal, _, _) = ReportHelpers.VnRange(from, to);
            var storeId = RequiredStoreId;

            var quotas = await db.ShiftStaffingQuotas
                .Where(q => q.StoreId == storeId
                    && (string.IsNullOrEmpty(department) || q.Department == department))
                .Select(q => new { q.ShiftTemplateId, ShiftName = q.ShiftTemplate.Name, q.Department, q.MinEmployees, q.MaxEmployees, q.WarningThreshold })
                .ToListAsync(ct);

            var scheduleCounts = await db.WorkSchedules
                .Where(ws => ws.StoreId == storeId && ws.Deleted == null
                    && !ws.IsDayOff && ws.ShiftId != null
                    && ws.Date >= fromLocal && ws.Date <= toLocal)
                .GroupBy(ws => new { ws.ShiftId, ws.Date })
                .Select(g => new { ShiftId = g.Key.ShiftId!.Value, g.Key.Date, Registered = g.Count() })
                .ToListAsync(ct);

            var items = new List<ShiftCoverageItemDto>();
            foreach (var q in quotas)
            {
                for (var d = fromLocal; d <= toLocal; d = d.AddDays(1))
                {
                    var registered = scheduleCounts
                        .Where(s => s.ShiftId == q.ShiftTemplateId && s.Date.Date == d)
                        .Sum(s => s.Registered);

                    var status = registered < q.MinEmployees ? "Thiếu"
                        : registered <= q.WarningThreshold ? "Cảnh báo"
                        : registered > q.MaxEmployees ? "Vượt" : "Đạt";

                    items.Add(new ShiftCoverageItemDto
                    {
                        Date = d,
                        ShiftId = q.ShiftTemplateId,
                        ShiftName = q.ShiftName ?? "-",
                        Department = q.Department ?? "(Toàn công ty)",
                        MinRequired = q.MinEmployees,
                        MaxAllowed = q.MaxEmployees,
                        Registered = registered,
                        Status = status,
                        Gap = Math.Max(0, q.MinEmployees - registered)
                    });
                }
            }

            var report = new ShiftCoverageReportDto
            {
                From = fromLocal, To = toLocal,
                Items = items.OrderBy(i => i.Date).ThenBy(i => i.ShiftName).ToList(),
                UnderCount = items.Count(i => i.Status == "Thiếu"),
                OverCount = items.Count(i => i.Status == "Vượt"),
                OkCount = items.Count(i => i.Status == "Đạt")
            };

            if (string.Equals(format, "excel", StringComparison.OrdinalIgnoreCase))
            {
                return ReportHelpers.ExcelFile("Shift coverage",
                    new[] { "Ngày", "Ca", "Phòng ban", "Min", "Max", "Đăng ký", "Thiếu", "Trạng thái" },
                    (ws, dataStartRow) => { int row = dataStartRow;
                        foreach (var i in report.Items)
                        {
                            ReportHelpers.DateCell(ws.Cell(row, 1), i.Date);
                            ws.Cell(row, 2).Value = i.ShiftName;
                            ws.Cell(row, 3).Value = i.Department;
                            ws.Cell(row, 4).Value = i.MinRequired;
                            ws.Cell(row, 5).Value = i.MaxAllowed;
                            ws.Cell(row, 6).Value = i.Registered;
                            ws.Cell(row, 7).Value = i.Gap;
                            ws.Cell(row, 8).Value = i.Status;
                            row++;
                        }
                    },
                    $"shift-coverage-{fromLocal:yyyyMMdd}-{toLocal:yyyyMMdd}.xlsx", user: User);
            }

            return Ok(AppResponse<ShiftCoverageReportDto>.Success(report));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Shift coverage failed");
            return StatusCode(500, AppResponse<ShiftCoverageReportDto>.Fail(ex.Message));
        }
    }

    // ═════════════════════════════════════════════════════════════════════
    // 4. SHIFT SWAPS — Tần suất đổi ca theo nhân viên
    // GET /api/reports/leave-shift/shift-swaps?from=&to=
    // ═════════════════════════════════════════════════════════════════════
    [HttpGet("shift-swaps")]
    [RequireModulePermission("LeaveReport", ModulePermissionAction.View)]
    public async Task<IActionResult> GetShiftSwaps(
        [FromQuery] DateTime? from = null,
        [FromQuery] DateTime? to = null,
        [FromQuery] string? format = null,
        CancellationToken ct = default)
    {
        try
        {
            var (fromLocal, toLocal, _, _) = ReportHelpers.VnRange(from, to);
            var storeId = RequiredStoreId;

            var swaps = await db.ShiftSwapRequests
                .Where(s => s.StoreId == storeId
                    && s.CreatedAt >= fromLocal && s.CreatedAt <= toLocal.AddDays(1))
                .Select(s => new { s.RequesterUserId, s.TargetUserId, s.Status, s.CreatedAt })
                .ToListAsync(ct);

            var userIds = swaps.Select(s => s.RequesterUserId)
                .Concat(swaps.Select(s => s.TargetUserId)).Distinct().ToList();
            var empLookup = await db.Employees
                .Where(e => e.ApplicationUserId.HasValue && userIds.Contains(e.ApplicationUserId!.Value))
                .Select(e => new { UserId = e.ApplicationUserId!.Value, e.EmployeeCode, e.FirstName, e.LastName, e.Department })
                .ToListAsync(ct);
            var byUser = empLookup.ToDictionary(e => e.UserId);

            var perEmp = swaps
                .GroupBy(s => s.RequesterUserId)
                .Select(g =>
                {
                    byUser.TryGetValue(g.Key, out var emp);
                    return new ShiftSwapItemDto
                    {
                        EmployeeCode = emp?.EmployeeCode ?? "-",
                        EmployeeName = emp == null ? "-" : ReportHelpers.FullName(emp.LastName, emp.FirstName),
                        Department = emp?.Department ?? "N/A",
                        TotalRequested = g.Count(),
                        Approved = g.Count(x => x.Status == ShiftSwapStatus.Approved),
                        Rejected = g.Count(x => x.Status == ShiftSwapStatus.RejectedByTarget || x.Status == ShiftSwapStatus.RejectedByManager),
                        Pending = g.Count(x => x.Status == ShiftSwapStatus.Pending || x.Status == ShiftSwapStatus.TargetAccepted)
                    };
                })
                .OrderByDescending(x => x.TotalRequested)
                .ToList();

            var report = new ShiftSwapReportDto
            {
                From = fromLocal, To = toLocal,
                TotalSwaps = swaps.Count,
                TotalApproved = swaps.Count(s => s.Status == ShiftSwapStatus.Approved),
                TotalRejected = swaps.Count(s => s.Status == ShiftSwapStatus.RejectedByTarget || s.Status == ShiftSwapStatus.RejectedByManager),
                Items = perEmp
            };

            if (string.Equals(format, "excel", StringComparison.OrdinalIgnoreCase))
            {
                return ReportHelpers.ExcelFile("Shift swaps",
                    new[] { "Mã NV", "Họ tên", "Phòng ban", "Yêu cầu", "Duyệt", "Từ chối", "Chờ" },
                    (ws, dataStartRow) => { int row = dataStartRow;
                        foreach (var i in perEmp)
                        {
                            ws.Cell(row, 1).Value = i.EmployeeCode;
                            ws.Cell(row, 2).Value = i.EmployeeName;
                            ws.Cell(row, 3).Value = i.Department;
                            ws.Cell(row, 4).Value = i.TotalRequested;
                            ws.Cell(row, 5).Value = i.Approved;
                            ws.Cell(row, 6).Value = i.Rejected;
                            ws.Cell(row, 7).Value = i.Pending;
                            row++;
                        }
                    },
                    $"shift-swaps-{fromLocal:yyyyMMdd}-{toLocal:yyyyMMdd}.xlsx", user: User);
            }

            return Ok(AppResponse<ShiftSwapReportDto>.Success(report));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Shift swap report failed");
            return StatusCode(500, AppResponse<ShiftSwapReportDto>.Fail(ex.Message));
        }
    }
}

// ══════════════════════════ DTOs (Cluster 2) ═══════════════════════════

public class LeaveBalanceReportDto
{
    public int Year { get; set; }
    public int TotalEmployees { get; set; }
    public List<LeaveBalanceItemDto> Items { get; set; } = new();
}
public class LeaveBalanceItemDto
{
    public Guid EmployeeId { get; set; }
    public string EmployeeCode { get; set; } = string.Empty;
    public string EmployeeName { get; set; } = string.Empty;
    public string Department { get; set; } = string.Empty;
    public decimal PaidEntitlement { get; set; }
    public decimal PaidUsed { get; set; }
    public decimal PaidRemaining { get; set; }
    public decimal UnpaidUsed { get; set; }
    public decimal SickUsed { get; set; }
    public decimal OtherUsed { get; set; }
    public double UsagePercent { get; set; }
}

public class LeaveApprovalSlaReportDto
{
    public DateTime From { get; set; }
    public DateTime To { get; set; }
    public int TotalRequests { get; set; }
    public int Approved { get; set; }
    public int Rejected { get; set; }
    public int Pending { get; set; }
    public int Cancelled { get; set; }
    public double ApprovalRate { get; set; }
    public double RejectionRate { get; set; }
    public double AvgResolutionHours { get; set; }
    public List<LeaveApproverSlaDto> Approvers { get; set; } = new();
}
public class LeaveApproverSlaDto
{
    public Guid ApproverId { get; set; }
    public string ApproverName { get; set; } = string.Empty;
    public int Total { get; set; }
    public int Approved { get; set; }
    public int Rejected { get; set; }
    public double AvgResponseHours { get; set; }
}

public class ShiftCoverageReportDto
{
    public DateTime From { get; set; }
    public DateTime To { get; set; }
    public int UnderCount { get; set; }
    public int OkCount { get; set; }
    public int OverCount { get; set; }
    public List<ShiftCoverageItemDto> Items { get; set; } = new();
}
public class ShiftCoverageItemDto
{
    public DateTime Date { get; set; }
    public Guid ShiftId { get; set; }
    public string ShiftName { get; set; } = string.Empty;
    public string Department { get; set; } = string.Empty;
    public int MinRequired { get; set; }
    public int MaxAllowed { get; set; }
    public int Registered { get; set; }
    public int Gap { get; set; }
    public string Status { get; set; } = string.Empty;
}

public class ShiftSwapReportDto
{
    public DateTime From { get; set; }
    public DateTime To { get; set; }
    public int TotalSwaps { get; set; }
    public int TotalApproved { get; set; }
    public int TotalRejected { get; set; }
    public List<ShiftSwapItemDto> Items { get; set; } = new();
}
public class ShiftSwapItemDto
{
    public string EmployeeCode { get; set; } = string.Empty;
    public string EmployeeName { get; set; } = string.Empty;
    public string Department { get; set; } = string.Empty;
    public int TotalRequested { get; set; }
    public int Approved { get; set; }
    public int Rejected { get; set; }
    public int Pending { get; set; }
}


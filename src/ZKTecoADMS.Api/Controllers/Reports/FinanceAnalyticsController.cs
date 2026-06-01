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
/// Cluster 6 — Finance Analytics:
/// penalty-summary, advance-debt, meal-debt.
/// </summary>
[ApiController]
[Route("api/reports/finance")]
[Authorize]
public class FinanceAnalyticsController(
    ZKTecoDbContext db,
    ILogger<FinanceAnalyticsController> logger
) : AuthenticatedControllerBase
{
    // ═════════════════════════════════════════════════════════════════════
    // 1. PENALTY SUMMARY — Tổng hợp phiếu phạt
    // GET /api/reports/finance/penalty-summary?from=&to=&department=&type=
    // ═════════════════════════════════════════════════════════════════════
    [HttpGet("penalty-summary")]
    [RequireModulePermission("PenaltyReport", ModulePermissionAction.View)]
    public async Task<IActionResult> GetPenaltySummary(
        [FromQuery] DateTime? from = null,
        [FromQuery] DateTime? to = null,
        [FromQuery] string? department = null,
        [FromQuery] PenaltyTicketType? type = null,
        [FromQuery] string? format = null,
        CancellationToken ct = default)
    {
        try
        {
            var (_, _, fromUtc, toUtc) = ReportHelpers.VnRange(from, to);
            var storeId = RequiredStoreId;

            var q = db.PenaltyTickets.IgnoreQueryFilters()
                .Where(p => p.StoreId == storeId
                    && p.ViolationDate >= fromUtc && p.ViolationDate < toUtc);
            if (type.HasValue) q = q.Where(p => p.Type == type.Value);

            var rows = await (from p in q
                              join e in db.Employees.IgnoreQueryFilters()
                                on p.EmployeeId equals e.Id
                              where e.StoreId == storeId
                              select new
                              {
                                  p.Id, p.TicketCode, p.Type, p.Status, p.Amount, p.ViolationDate,
                                  p.MinutesLateOrEarly, p.PenaltyTier,
                                  e.EmployeeCode, e.FirstName, e.LastName, e.Department
                              }).ToListAsync(ct);

            if (!string.IsNullOrWhiteSpace(department))
                rows = rows.Where(r => (r.Department ?? "").Contains(department, StringComparison.OrdinalIgnoreCase)).ToList();

            var byType = rows.GroupBy(r => r.Type)
                .Select(g => new PenaltyTypeItemDto
                {
                    Type = g.Key.ToString(),
                    Count = g.Count(),
                    TotalAmount = g.Sum(x => x.Amount),
                    AvgAmount = Math.Round(g.Average(x => x.Amount), 0)
                })
                .OrderByDescending(i => i.TotalAmount).ToList();

            var byStatus = rows.GroupBy(r => r.Status)
                .Select(g => new PenaltyStatusItemDto
                {
                    Status = g.Key.ToString(),
                    Count = g.Count(),
                    TotalAmount = g.Sum(x => x.Amount)
                }).ToList();

            var byEmployee = rows.GroupBy(r => new { r.EmployeeCode, r.FirstName, r.LastName, r.Department })
                .Select(g => new PenaltyEmployeeItemDto
                {
                    EmployeeCode = g.Key.EmployeeCode,
                    EmployeeName = ReportHelpers.FullName(g.Key.LastName, g.Key.FirstName),
                    Department = g.Key.Department ?? "N/A",
                    TicketCount = g.Count(),
                    TotalAmount = g.Sum(x => x.Amount),
                    LateCount = g.Count(x => x.Type == PenaltyTicketType.Late),
                    EarlyCount = g.Count(x => x.Type == PenaltyTicketType.EarlyLeave),
                    ForgotCount = g.Count(x => x.Type == PenaltyTicketType.ForgotCheck),
                    OtherCount = g.Count(x => x.Type != PenaltyTicketType.Late
                        && x.Type != PenaltyTicketType.EarlyLeave
                        && x.Type != PenaltyTicketType.ForgotCheck)
                })
                .OrderByDescending(i => i.TotalAmount)
                .ToList();

            var report = new PenaltySummaryReportDto
            {
                From = ReportHelpers.ToVn(fromUtc),
                To = ReportHelpers.ToVn(toUtc.AddTicks(-1)),
                TotalTickets = rows.Count,
                TotalAmount = rows.Sum(r => r.Amount),
                ApprovedAmount = rows.Where(r => r.Status == PenaltyTicketStatus.Approved || r.Status == PenaltyTicketStatus.AutoApproved).Sum(r => r.Amount),
                CancelledAmount = rows.Where(r => r.Status == PenaltyTicketStatus.Cancelled).Sum(r => r.Amount),
                ByType = byType,
                ByStatus = byStatus,
                ByEmployee = byEmployee
            };

            if (string.Equals(format, "excel", StringComparison.OrdinalIgnoreCase))
            {
                return ReportHelpers.ExcelFile("Phiếu phạt",
                    new[] { "Mã NV", "Họ tên", "Phòng ban", "Số phiếu", "Tổng tiền", "Đi trễ", "Về sớm", "Quên chấm", "Khác" },
                    (ws, dataStartRow) => { int row = dataStartRow;
                        foreach (var i in byEmployee)
                        {
                            ws.Cell(row, 1).Value = i.EmployeeCode;
                            ws.Cell(row, 2).Value = i.EmployeeName;
                            ws.Cell(row, 3).Value = i.Department;
                            ws.Cell(row, 4).Value = i.TicketCount;
                            ReportHelpers.MoneyCell(ws.Cell(row, 5), i.TotalAmount);
                            ws.Cell(row, 6).Value = i.LateCount;
                            ws.Cell(row, 7).Value = i.EarlyCount;
                            ws.Cell(row, 8).Value = i.ForgotCount;
                            ws.Cell(row, 9).Value = i.OtherCount;
                            row++;
                        }
                    },
                    $"penalty-summary-{report.From:yyyyMMdd}-{report.To:yyyyMMdd}.xlsx", user: User);
            }

            return Ok(AppResponse<PenaltySummaryReportDto>.Success(report));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Penalty summary failed");
            return StatusCode(500, AppResponse<PenaltySummaryReportDto>.Fail(ex.Message));
        }
    }

    // ═════════════════════════════════════════════════════════════════════
    // 2. ADVANCE DEBT — Dư nợ ứng lương
    // GET /api/reports/finance/advance-debt?from=&to=&department=&status=
    // ═════════════════════════════════════════════════════════════════════
    [HttpGet("advance-debt")]
    [RequireModulePermission("AdvanceReport", ModulePermissionAction.View)]
    public async Task<IActionResult> GetAdvanceDebt(
        [FromQuery] DateTime? from = null,
        [FromQuery] DateTime? to = null,
        [FromQuery] string? department = null,
        [FromQuery] AdvanceRequestStatus? status = null,
        [FromQuery] string? format = null,
        CancellationToken ct = default)
    {
        try
        {
            var (_, _, fromUtc, toUtc) = ReportHelpers.VnRange(from, to);
            var storeId = RequiredStoreId;

            var q = db.AdvanceRequests.IgnoreQueryFilters()
                .Where(a => a.StoreId == storeId
                    && a.RequestDate >= fromUtc && a.RequestDate < toUtc);
            if (status.HasValue) q = q.Where(a => a.Status == status.Value);

            var rows = await (from a in q
                              join e in db.Employees.IgnoreQueryFilters()
                                on a.EmployeeId equals e.Id into gj
                              from emp in gj.DefaultIfEmpty()
                              where emp == null || emp.StoreId == storeId
                              select new
                              {
                                  a.Id, a.Amount, a.Status, a.RequestDate, a.ApprovedDate, a.IsPaid, a.PaidDate,
                                  a.ForMonth, a.ForYear,
                                  EmployeeCode = emp != null ? emp.EmployeeCode : "-",
                                  FirstName = emp != null ? emp.FirstName : "",
                                  LastName = emp != null ? emp.LastName : "",
                                  Department = emp != null ? emp.Department : null
                              }).ToListAsync(ct);

            if (!string.IsNullOrWhiteSpace(department))
                rows = rows.Where(r => (r.Department ?? "").Contains(department, StringComparison.OrdinalIgnoreCase)).ToList();

            var approvedButUnpaid = rows.Where(r => r.Status == AdvanceRequestStatus.Approved && !r.IsPaid).Sum(r => r.Amount);
            var paid = rows.Where(r => r.IsPaid).Sum(r => r.Amount);
            var pending = rows.Where(r => r.Status == AdvanceRequestStatus.Pending).Sum(r => r.Amount);
            var rejected = rows.Where(r => r.Status == AdvanceRequestStatus.Rejected).Sum(r => r.Amount);

            var byEmployee = rows
                .Where(r => r.Status != AdvanceRequestStatus.Rejected && r.Status != AdvanceRequestStatus.Cancelled)
                .GroupBy(r => new { r.EmployeeCode, r.FirstName, r.LastName, r.Department })
                .Select(g => new AdvanceDebtEmployeeDto
                {
                    EmployeeCode = g.Key.EmployeeCode,
                    EmployeeName = ReportHelpers.FullName(g.Key.LastName, g.Key.FirstName),
                    Department = g.Key.Department ?? "N/A",
                    TotalRequests = g.Count(),
                    TotalApproved = g.Where(x => x.Status == AdvanceRequestStatus.Approved).Sum(x => x.Amount),
                    TotalPaid = g.Where(x => x.IsPaid).Sum(x => x.Amount),
                    OutstandingDebt = g.Where(x => x.Status == AdvanceRequestStatus.Approved && !x.IsPaid).Sum(x => x.Amount)
                })
                .OrderByDescending(i => i.OutstandingDebt)
                .ToList();

            var report = new AdvanceDebtReportDto
            {
                From = ReportHelpers.ToVn(fromUtc),
                To = ReportHelpers.ToVn(toUtc.AddTicks(-1)),
                TotalRequests = rows.Count,
                PendingAmount = pending,
                ApprovedUnpaid = approvedButUnpaid,
                PaidAmount = paid,
                RejectedAmount = rejected,
                Items = byEmployee
            };

            if (string.Equals(format, "excel", StringComparison.OrdinalIgnoreCase))
            {
                return ReportHelpers.ExcelFile("Ứng lương",
                    new[] { "Mã NV", "Họ tên", "Phòng ban", "Số lần", "Đã duyệt", "Đã trả", "Dư nợ" },
                    (ws, dataStartRow) => { int row = dataStartRow;
                        foreach (var i in byEmployee)
                        {
                            ws.Cell(row, 1).Value = i.EmployeeCode;
                            ws.Cell(row, 2).Value = i.EmployeeName;
                            ws.Cell(row, 3).Value = i.Department;
                            ws.Cell(row, 4).Value = i.TotalRequests;
                            ReportHelpers.MoneyCell(ws.Cell(row, 5), i.TotalApproved);
                            ReportHelpers.MoneyCell(ws.Cell(row, 6), i.TotalPaid);
                            ReportHelpers.MoneyCell(ws.Cell(row, 7), i.OutstandingDebt);
                            row++;
                        }
                    },
                    $"advance-debt-{report.From:yyyyMMdd}-{report.To:yyyyMMdd}.xlsx", user: User);
            }

            return Ok(AppResponse<AdvanceDebtReportDto>.Success(report));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Advance debt failed");
            return StatusCode(500, AppResponse<AdvanceDebtReportDto>.Fail(ex.Message));
        }
    }

    // ═════════════════════════════════════════════════════════════════════
    // 3. MEAL DEBT — Công nợ suất ăn
    // GET /api/reports/finance/meal-debt?period=yyyy-MM or from/to
    // ═════════════════════════════════════════════════════════════════════
    [HttpGet("meal-debt")]
    [RequireModulePermission("Meal", ModulePermissionAction.View)]
    public async Task<IActionResult> GetMealDebt(
        [FromQuery] string? period = null,
        [FromQuery] DateTime? from = null,
        [FromQuery] DateTime? to = null,
        [FromQuery] string? format = null,
        CancellationToken ct = default)
    {
        try
        {
            var storeId = RequiredStoreId;

            IQueryable<Domain.Entities.MealDebt> q = db.MealDebts.IgnoreQueryFilters()
                .Where(m => m.StoreId == storeId);

            if (!string.IsNullOrWhiteSpace(period))
            {
                q = q.Where(m => m.Period == period);
            }
            else
            {
                var (_, _, fromUtc, toUtc) = ReportHelpers.VnRange(from, to);
                q = q.Where(m => m.Date >= fromUtc && m.Date < toUtc);
            }

            var rows = await (from m in q
                              join e in db.Employees.IgnoreQueryFilters()
                                on m.EmployeeUserId equals e.ApplicationUserId into gj
                              from emp in gj.DefaultIfEmpty()
                              select new
                              {
                                  m.EmployeeUserId, m.Type, m.Amount, m.Date, m.Period, m.EmployeeName,
                                  EmployeeCode = emp != null ? emp.EmployeeCode : "-",
                                  Department = emp != null ? emp.Department : null
                              }).ToListAsync(ct);

            var byEmployee = rows
                .GroupBy(r => new { r.EmployeeUserId, r.EmployeeName, r.EmployeeCode, r.Department })
                .Select(g => new MealDebtEmployeeDto
                {
                    EmployeeCode = g.Key.EmployeeCode,
                    EmployeeName = g.Key.EmployeeName,
                    Department = g.Key.Department ?? "N/A",
                    TotalCharge = g.Where(x => x.Type == 0).Sum(x => x.Amount),
                    TotalPayment = g.Where(x => x.Type == 1).Sum(x => x.Amount),
                    OutstandingDebt = g.Where(x => x.Type == 0).Sum(x => x.Amount) - g.Where(x => x.Type == 1).Sum(x => x.Amount),
                    LastTransactionDate = ReportHelpers.ToVn(g.Max(x => x.Date))
                })
                .OrderByDescending(i => i.OutstandingDebt)
                .ToList();

            var report = new MealDebtReportDto
            {
                Period = period,
                TotalEmployees = byEmployee.Count,
                TotalCharge = byEmployee.Sum(i => i.TotalCharge),
                TotalPayment = byEmployee.Sum(i => i.TotalPayment),
                TotalOutstanding = byEmployee.Sum(i => i.OutstandingDebt),
                Items = byEmployee
            };

            if (string.Equals(format, "excel", StringComparison.OrdinalIgnoreCase))
            {
                return ReportHelpers.ExcelFile($"Công nợ ăn {period ?? "period"}",
                    new[] { "Mã NV", "Họ tên", "Phòng ban", "Phát sinh", "Đã thu", "Dư nợ", "GD gần nhất" },
                    (ws, dataStartRow) => { int row = dataStartRow;
                        foreach (var i in byEmployee)
                        {
                            ws.Cell(row, 1).Value = i.EmployeeCode;
                            ws.Cell(row, 2).Value = i.EmployeeName;
                            ws.Cell(row, 3).Value = i.Department;
                            ReportHelpers.MoneyCell(ws.Cell(row, 4), i.TotalCharge);
                            ReportHelpers.MoneyCell(ws.Cell(row, 5), i.TotalPayment);
                            ReportHelpers.MoneyCell(ws.Cell(row, 6), i.OutstandingDebt);
                            ReportHelpers.DateCell(ws.Cell(row, 7), i.LastTransactionDate);
                            row++;
                        }
                    },
                    $"meal-debt-{period ?? "range"}.xlsx", user: User);
            }

            return Ok(AppResponse<MealDebtReportDto>.Success(report));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Meal debt failed");
            return StatusCode(500, AppResponse<MealDebtReportDto>.Fail(ex.Message));
        }
    }
}

// ═══════════════════════════ DTOs ═══════════════════════════

public class PenaltySummaryReportDto
{
    public DateTime From { get; set; }
    public DateTime To { get; set; }
    public int TotalTickets { get; set; }
    public decimal TotalAmount { get; set; }
    public decimal ApprovedAmount { get; set; }
    public decimal CancelledAmount { get; set; }
    public List<PenaltyTypeItemDto> ByType { get; set; } = new();
    public List<PenaltyStatusItemDto> ByStatus { get; set; } = new();
    public List<PenaltyEmployeeItemDto> ByEmployee { get; set; } = new();
}
public class PenaltyTypeItemDto
{
    public string Type { get; set; } = string.Empty;
    public int Count { get; set; }
    public decimal TotalAmount { get; set; }
    public decimal AvgAmount { get; set; }
}
public class PenaltyStatusItemDto
{
    public string Status { get; set; } = string.Empty;
    public int Count { get; set; }
    public decimal TotalAmount { get; set; }
}
public class PenaltyEmployeeItemDto
{
    public string EmployeeCode { get; set; } = string.Empty;
    public string EmployeeName { get; set; } = string.Empty;
    public string Department { get; set; } = string.Empty;
    public int TicketCount { get; set; }
    public decimal TotalAmount { get; set; }
    public int LateCount { get; set; }
    public int EarlyCount { get; set; }
    public int ForgotCount { get; set; }
    public int OtherCount { get; set; }
}

public class AdvanceDebtReportDto
{
    public DateTime From { get; set; }
    public DateTime To { get; set; }
    public int TotalRequests { get; set; }
    public decimal PendingAmount { get; set; }
    public decimal ApprovedUnpaid { get; set; }
    public decimal PaidAmount { get; set; }
    public decimal RejectedAmount { get; set; }
    public List<AdvanceDebtEmployeeDto> Items { get; set; } = new();
}
public class AdvanceDebtEmployeeDto
{
    public string EmployeeCode { get; set; } = string.Empty;
    public string EmployeeName { get; set; } = string.Empty;
    public string Department { get; set; } = string.Empty;
    public int TotalRequests { get; set; }
    public decimal TotalApproved { get; set; }
    public decimal TotalPaid { get; set; }
    public decimal OutstandingDebt { get; set; }
}

public class MealDebtReportDto
{
    public string? Period { get; set; }
    public int TotalEmployees { get; set; }
    public decimal TotalCharge { get; set; }
    public decimal TotalPayment { get; set; }
    public decimal TotalOutstanding { get; set; }
    public List<MealDebtEmployeeDto> Items { get; set; } = new();
}
public class MealDebtEmployeeDto
{
    public string EmployeeCode { get; set; } = string.Empty;
    public string EmployeeName { get; set; } = string.Empty;
    public string Department { get; set; } = string.Empty;
    public decimal TotalCharge { get; set; }
    public decimal TotalPayment { get; set; }
    public decimal OutstandingDebt { get; set; }
    public DateTime LastTransactionDate { get; set; }
}


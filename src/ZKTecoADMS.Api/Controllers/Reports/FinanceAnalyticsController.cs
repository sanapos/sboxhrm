using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
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

            var activeRows = rows
                .Where(r => r.Status != PenaltyTicketStatus.Cancelled)
                .ToList();

            var byType = activeRows.GroupBy(r => r.Type)
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

            var byEmployee = activeRows.GroupBy(r => new { r.EmployeeCode, r.FirstName, r.LastName, r.Department })
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
                TotalTickets = activeRows.Count,
                TotalAmount = activeRows.Sum(r => r.Amount),
                ApprovedAmount = activeRows.Where(r => r.Status == PenaltyTicketStatus.Approved || r.Status == PenaltyTicketStatus.AutoApproved).Sum(r => r.Amount),
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

            var activeRows = rows
                .Where(r => r.Status != AdvanceRequestStatus.Rejected && r.Status != AdvanceRequestStatus.Cancelled)
                .ToList();

            var approvedButUnpaid = activeRows.Where(r => r.Status == AdvanceRequestStatus.Approved && !r.IsPaid).Sum(r => r.Amount);
            var paid = activeRows.Where(r => r.IsPaid).Sum(r => r.Amount);
            var pending = activeRows.Where(r => r.Status == AdvanceRequestStatus.Pending).Sum(r => r.Amount);
            var rejected = rows.Where(r => r.Status == AdvanceRequestStatus.Rejected).Sum(r => r.Amount);

            var byEmployee = activeRows
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
                TotalRequests = activeRows.Count,
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
    // 2b. BUSINESS TRIP — Báo cáo công tác phí
    // GET /api/reports/finance/business-trip?from=&to=&department=&status=
    // ═════════════════════════════════════════════════════════════════════
    [HttpGet("business-trip")]
    [RequireModulePermission("BusinessTripReport", ModulePermissionAction.View)]
    public async Task<IActionResult> GetBusinessTripReport(
        [FromQuery] DateTime? from = null,
        [FromQuery] DateTime? to = null,
        [FromQuery] string? department = null,
        [FromQuery] BusinessTripCaseStatus? status = null,
        [FromQuery] string? format = null,
        CancellationToken ct = default)
    {
        try
        {
            var (_, _, fromUtc, toUtc) = ReportHelpers.VnRange(from, to);
            var storeId = RequiredStoreId;

            Guid? employeeUserFilter = null;
            if (!IsBusinessTripPrivileged)
                employeeUserFilter = CurrentUserId;

            var q = db.BusinessTripCases.IgnoreQueryFilters()
                .Include(c => c.Employee)
                .Include(c => c.EmployeeUser)
                .Include(c => c.AdvanceClaim)
                .Include(c => c.SettlementClaim!)
                    .ThenInclude(s => s.Lines)
                        .ThenInclude(l => l.Category)
                .Where(c => c.StoreId == storeId
                    && c.Deleted == null
                    && c.CreatedAt >= fromUtc && c.CreatedAt < toUtc);

            if (status.HasValue)
                q = q.Where(c => c.Status == status.Value);
            else
                q = q.Where(c => c.Status != BusinessTripCaseStatus.Cancelled);
            if (employeeUserFilter.HasValue)
                q = q.Where(c => c.EmployeeUserId == employeeUserFilter);

            var cases = await q.OrderByDescending(c => c.CreatedAt).ToListAsync(ct);

            if (!string.IsNullOrWhiteSpace(department))
            {
                cases = cases.Where(c =>
                    (c.Employee?.Department ?? "").Contains(department, StringComparison.OrdinalIgnoreCase))
                    .ToList();
            }

            // Mặc định đã loại Cancelled ở query; active dùng cho tổng hợp (bỏ hủy nếu lọc riêng status=Cancelled).
            var active = cases.Where(c => c.Status != BusinessTripCaseStatus.Cancelled).ToList();

            var items = cases.Select(c =>
            {
                var emp = c.Employee;
                var empName = emp != null
                    ? ReportHelpers.FullName(emp.LastName, emp.FirstName)
                    : c.EmployeeUser != null
                        ? ReportHelpers.FullName(c.EmployeeUser.LastName, c.EmployeeUser.FirstName)
                        : "—";
                var claim = c.SettlementClaim;
                var lines = claim?.Lines?.Where(l => l.Deleted == null).ToList() ?? [];
                return new BusinessTripReportItemDto
                {
                    Id = c.Id,
                    CaseCode = c.CaseCode,
                    Title = c.Title,
                    Destination = c.Destination,
                    EmployeeUserId = c.EmployeeUserId,
                    EmployeeCode = emp?.EmployeeCode ?? "—",
                    EmployeeName = empName,
                    Department = emp?.Department ?? "N/A",
                    Status = c.Status,
                    StatusLabel = BusinessTripStatusLabel(c.Status),
                    AdvanceAmount = c.AdvanceAmount,
                    SettledAmount = c.SettledAmount,
                    BalanceAmount = c.BalanceAmount,
                    TripFromDate = c.TripFromDate,
                    TripToDate = c.TripToDate,
                    CreatedAt = c.CreatedAt,
                    AdvanceIsPaid = c.AdvanceClaim?.IsPaid ?? false,
                    AdvanceStatus = c.AdvanceClaim?.Status,
                    SettlementStatus = claim?.Status,
                    SettlementType = claim?.SettlementType,
                    ExpenseLineCount = lines.Count,
                    TotalWithInvoice = claim?.TotalWithInvoice
                        ?? lines.Where(l => l.HasInvoice).Sum(l => l.Amount),
                    TotalWithoutInvoice = claim?.TotalWithoutInvoice
                        ?? lines.Where(l => !l.HasInvoice).Sum(l => l.Amount),
                    CategoryIds = lines
                        .Where(l => l.CategoryId.HasValue)
                        .Select(l => l.CategoryId!.Value)
                        .Distinct()
                        .ToList(),
                    HasUncategorizedExpense = lines.Any(l => l.CategoryId == null)
                };
            }).ToList();

            var byEmployee = active
                .GroupBy(c =>
                {
                    var emp = c.Employee;
                    var code = emp?.EmployeeCode ?? "—";
                    var name = emp != null
                        ? ReportHelpers.FullName(emp.LastName, emp.FirstName)
                        : c.EmployeeUser != null
                            ? ReportHelpers.FullName(c.EmployeeUser.LastName, c.EmployeeUser.FirstName)
                            : "—";
                    return new { code, name, dept = emp?.Department ?? "N/A" };
                })
                .Select(g => new BusinessTripReportEmployeeDto
                {
                    EmployeeCode = g.Key.code,
                    EmployeeName = g.Key.name,
                    Department = g.Key.dept,
                    TotalCases = g.Count(),
                    TotalAdvance = g.Sum(x => x.AdvanceAmount),
                    TotalSettled = g.Sum(x => x.SettledAmount),
                    TotalBalance = g.Sum(x => x.BalanceAmount),
                    PendingAdvance = g.Count(x => x.Status == BusinessTripCaseStatus.AdvancePending),
                    PendingSettlement = g.Count(x => x.Status == BusinessTripCaseStatus.SettlementPending),
                    ClosedCases = g.Count(x => x.Status == BusinessTripCaseStatus.Closed)
                })
                .OrderByDescending(i => i.TotalSettled)
                .ThenByDescending(i => i.TotalAdvance)
                .ToList();

            // Tổng hợp theo hạng mục chi phí từ dòng hoạch toán của hồ sơ active.
            var expenseLines = active
                .SelectMany(c => (c.SettlementClaim?.Lines ?? Enumerable.Empty<BusinessTripExpenseLine>())
                    .Where(l => l.Deleted == null)
                    .Select(l => new { CaseId = c.Id, Line = l }))
                .ToList();
            var expenseTotal = expenseLines.Sum(x => x.Line.Amount);
            var byCategory = expenseLines
                .GroupBy(x => new
                {
                    CategoryId = x.Line.CategoryId,
                    Name = string.IsNullOrWhiteSpace(x.Line.Category?.Name)
                        ? "Không phân loại"
                        : x.Line.Category!.Name!,
                    Code = x.Line.Category?.Code
                })
                .Select(g =>
                {
                    var total = g.Sum(x => x.Line.Amount);
                    return new BusinessTripReportCategoryDto
                    {
                        CategoryId = g.Key.CategoryId,
                        CategoryCode = g.Key.Code,
                        CategoryName = g.Key.Name,
                        LineCount = g.Count(),
                        CaseCount = g.Select(x => x.CaseId).Distinct().Count(),
                        TotalAmount = total,
                        WithInvoiceAmount = g.Where(x => x.Line.HasInvoice).Sum(x => x.Line.Amount),
                        WithoutInvoiceAmount = g.Where(x => !x.Line.HasInvoice).Sum(x => x.Line.Amount),
                        Percentage = expenseTotal > 0
                            ? Math.Round(total * 100m / expenseTotal, 1)
                            : 0
                    };
                })
                .OrderByDescending(i => i.TotalAmount)
                .ThenBy(i => i.CategoryName)
                .ToList();

            var report = new BusinessTripReportDto
            {
                From = ReportHelpers.ToVn(fromUtc),
                To = ReportHelpers.ToVn(toUtc.AddTicks(-1)),
                TotalCases = active.Count,
                PendingAdvanceCases = active.Count(c => c.Status == BusinessTripCaseStatus.AdvancePending),
                PendingSettlementCases = active.Count(c => c.Status == BusinessTripCaseStatus.SettlementPending),
                ClosedCases = active.Count(c => c.Status == BusinessTripCaseStatus.Closed),
                TotalAdvanceAmount = active.Sum(c => c.AdvanceAmount),
                TotalSettledAmount = active.Sum(c => c.SettledAmount),
                TotalBalanceAmount = active.Sum(c => c.BalanceAmount),
                TotalWithInvoice = active.Sum(c =>
                    c.SettlementClaim?.TotalWithInvoice
                    ?? (c.SettlementClaim?.Lines?.Where(l => l.Deleted == null && l.HasInvoice).Sum(l => l.Amount) ?? 0)),
                TotalWithoutInvoice = active.Sum(c =>
                    c.SettlementClaim?.TotalWithoutInvoice
                    ?? (c.SettlementClaim?.Lines?.Where(l => l.Deleted == null && !l.HasInvoice).Sum(l => l.Amount) ?? 0)),
                ExpenseLineCount = expenseLines.Count,
                Items = items,
                ByEmployee = byEmployee,
                ByCategory = byCategory
            };

            if (string.Equals(format, "excel", StringComparison.OrdinalIgnoreCase))
            {
                return ReportHelpers.ExcelFile("Công tác phí",
                    new[] { "Mã HS", "Tiêu đề", "Mã NV", "Họ tên", "Phòng ban", "Điểm đến", "Trạng thái", "Đã ứng", "Hoạch toán", "Chênh lệch", "Ngày tạo" },
                    (ws, dataStartRow) =>
                    {
                        int row = dataStartRow;
                        foreach (var i in items)
                        {
                            ws.Cell(row, 1).Value = i.CaseCode;
                            ws.Cell(row, 2).Value = i.Title;
                            ws.Cell(row, 3).Value = i.EmployeeCode;
                            ws.Cell(row, 4).Value = i.EmployeeName;
                            ws.Cell(row, 5).Value = i.Department;
                            ws.Cell(row, 6).Value = i.Destination ?? "";
                            ws.Cell(row, 7).Value = i.StatusLabel;
                            ReportHelpers.MoneyCell(ws.Cell(row, 8), i.AdvanceAmount);
                            ReportHelpers.MoneyCell(ws.Cell(row, 9), i.SettledAmount);
                            ReportHelpers.MoneyCell(ws.Cell(row, 10), i.BalanceAmount);
                            ws.Cell(row, 11).Value = i.CreatedAt.ToString("dd/MM/yyyy");
                            row++;
                        }
                    },
                    $"business-trip-{report.From:yyyyMMdd}-{report.To:yyyyMMdd}.xlsx", user: User);
            }

            return Ok(AppResponse<BusinessTripReportDto>.Success(report));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Business trip report failed");
            return StatusCode(500, AppResponse<BusinessTripReportDto>.Fail(ex.Message));
        }
    }

    private static string BusinessTripStatusLabel(BusinessTripCaseStatus status) => status switch
    {
        BusinessTripCaseStatus.Draft => "Nháp",
        BusinessTripCaseStatus.AdvancePending => "Chờ duyệt ứng",
        BusinessTripCaseStatus.AdvanceApproved => "Ứng đã duyệt",
        BusinessTripCaseStatus.AdvancePaid => "Đã chi ứng",
        BusinessTripCaseStatus.SettlementDraft => "Nháp HT",
        BusinessTripCaseStatus.SettlementPending => "Chờ duyệt HT",
        BusinessTripCaseStatus.SettlementApproved => "HT đã duyệt",
        BusinessTripCaseStatus.Settling => "Quyết toán",
        BusinessTripCaseStatus.Closed => "Đóng",
        BusinessTripCaseStatus.Cancelled => "Hủy",
        _ => status.ToString()
    };

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

    // ═════════════════════════════════════════════════════════════════════
    // 4. CASH TRANSACTIONS — Báo cáo thu chi (quyền CashReport)
    // GET /api/reports/finance/cash-transactions?from=&to=&type=
    // ═════════════════════════════════════════════════════════════════════
    [HttpGet("cash-transactions")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("CashReport", ModulePermissionAction.View)]
    public async Task<IActionResult> GetCashTransactionsReport(
        [FromQuery] DateTime? from = null,
        [FromQuery] DateTime? to = null,
        [FromQuery] CashTransactionType? type = null,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 500,
        CancellationToken ct = default)
    {
        try
        {
            // TransactionDate lưu theo ngày lịch VN (không phải UTC punch) — lọc theo ngày local.
            var (fromLocal, toLocal, _, _) = ReportHelpers.VnRange(from, to);
            var rangeStart = fromLocal.Date;
            var rangeEndExclusive = toLocal.Date.AddDays(1);
            var storeId = RequiredStoreId;

            var query = db.CashTransactions.IgnoreQueryFilters()
                .Include(x => x.Category)
                .Include(x => x.CreatedByUser)
                .Where(x => x.StoreId == storeId && x.IsActive
                    && x.TransactionDate >= rangeStart
                    && x.TransactionDate < rangeEndExclusive);

            if (type.HasValue)
                query = query.Where(x => x.Type == type.Value);

            if (IsEmployee && !IsManager)
            {
                var empId = EmployeeId;
                if (!empId.HasValue)
                {
                    return Ok(AppResponse<CashReportListDto>.Success(new CashReportListDto
                    {
                        Page = page,
                        PageSize = pageSize
                    }));
                }

                var linkedTxIds = await db.PenaltyTickets.IgnoreQueryFilters()
                    .Where(p => p.StoreId == storeId && p.EmployeeId == empId.Value
                        && p.CashTransactionId != null)
                    .Select(p => p.CashTransactionId!.Value)
                    .Distinct()
                    .ToListAsync(ct);

                query = query.Where(x =>
                    linkedTxIds.Contains(x.Id) || x.CreatedByUserId == CurrentUserId);
            }

            var total = await query.CountAsync(ct);

            var rangeRows = await query.ToListAsync(ct);
            var summary = BuildCashReportSummary(rangeRows);

            var items = rangeRows
                .OrderByDescending(x => x.TransactionDate)
                .Skip((page - 1) * pageSize)
                .Take(pageSize)
                .Select(MapCashReportItem)
                .ToList();

            return Ok(AppResponse<CashReportListDto>.Success(new CashReportListDto
            {
                Items = items,
                PendingItems = new List<CashReportItemDto>(),
                TotalCount = total,
                Page = page,
                PageSize = pageSize,
                Summary = summary
            }));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Cash report transactions failed");
            return StatusCode(500, AppResponse<CashReportListDto>.Fail(ex.Message));
        }
    }

    private static CashReportItemDto MapCashReportItem(CashTransaction x) => new()
    {
        Id = x.Id,
        TransactionCode = x.TransactionCode,
        Type = (int)x.Type,
        CategoryId = x.CategoryId,
        CategoryName = x.Category != null ? x.Category.Name : "",
        Amount = x.Amount,
        TransactionDate = x.TransactionDate,
        Description = x.Description,
        PaymentMethod = (int)x.PaymentMethod,
        Status = x.IsPaid ? (int)CashTransactionStatus.Completed : (int)x.Status,
        IsPaid = x.IsPaid,
        CreatedByUserName = x.CreatedByUser != null ? (x.CreatedByUser.UserName ?? "") : ""
    };

    private static CashReportSummaryDto BuildCashReportSummary(List<CashTransaction> rows)
    {
        static bool IsCompleted(CashTransaction x) =>
            x.IsPaid || x.Status == CashTransactionStatus.Completed;

        static bool IsCancelled(CashTransaction x) =>
            x.Status == CashTransactionStatus.Cancelled;

        var paidIncome = rows.Where(x => !IsCancelled(x) && IsCompleted(x) && x.Type == CashTransactionType.Income);
        var paidExpense = rows.Where(x => !IsCancelled(x) && IsCompleted(x) && x.Type == CashTransactionType.Expense);
        var pendingInRange = rows.Where(x => !IsCancelled(x) && !IsCompleted(x)
            && (x.Status == CashTransactionStatus.Pending || x.Status == CashTransactionStatus.WaitingPayment));
        var cancelled = rows.Where(IsCancelled);

        return new CashReportSummaryDto
        {
            PaidIncome = paidIncome.Sum(x => x.Amount),
            PaidExpense = paidExpense.Sum(x => x.Amount),
            PaidIncomeCount = paidIncome.Count(),
            PaidExpenseCount = paidExpense.Count(),
            PendingIncome = pendingInRange.Where(x => x.Type == CashTransactionType.Income).Sum(x => x.Amount),
            PendingExpense = pendingInRange.Where(x => x.Type == CashTransactionType.Expense).Sum(x => x.Amount),
            PendingIncomeCount = pendingInRange.Count(x => x.Type == CashTransactionType.Income),
            PendingExpenseCount = pendingInRange.Count(x => x.Type == CashTransactionType.Expense),
            CancelledCount = cancelled.Count()
        };
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

public class BusinessTripReportDto
{
    public DateTime From { get; set; }
    public DateTime To { get; set; }
    public int TotalCases { get; set; }
    public int PendingAdvanceCases { get; set; }
    public int PendingSettlementCases { get; set; }
    public int ClosedCases { get; set; }
    public decimal TotalAdvanceAmount { get; set; }
    public decimal TotalSettledAmount { get; set; }
    public decimal TotalBalanceAmount { get; set; }
    public decimal TotalWithInvoice { get; set; }
    public decimal TotalWithoutInvoice { get; set; }
    public int ExpenseLineCount { get; set; }
    public List<BusinessTripReportItemDto> Items { get; set; } = new();
    public List<BusinessTripReportEmployeeDto> ByEmployee { get; set; } = new();
    public List<BusinessTripReportCategoryDto> ByCategory { get; set; } = new();
}

public class BusinessTripReportItemDto
{
    public Guid Id { get; set; }
    public string CaseCode { get; set; } = string.Empty;
    public string Title { get; set; } = string.Empty;
    public string? Destination { get; set; }
    public Guid? EmployeeUserId { get; set; }
    public string EmployeeCode { get; set; } = string.Empty;
    public string EmployeeName { get; set; } = string.Empty;
    public string Department { get; set; } = string.Empty;
    public BusinessTripCaseStatus Status { get; set; }
    public string StatusLabel { get; set; } = string.Empty;
    public decimal AdvanceAmount { get; set; }
    public decimal SettledAmount { get; set; }
    public decimal BalanceAmount { get; set; }
    public DateTime? TripFromDate { get; set; }
    public DateTime? TripToDate { get; set; }
    public DateTime CreatedAt { get; set; }
    public bool AdvanceIsPaid { get; set; }
    public AdvanceRequestStatus? AdvanceStatus { get; set; }
    public AdvanceRequestStatus? SettlementStatus { get; set; }
    public BusinessTripSettlementType? SettlementType { get; set; }
    public int ExpenseLineCount { get; set; }
    public decimal TotalWithInvoice { get; set; }
    public decimal TotalWithoutInvoice { get; set; }
    public List<Guid> CategoryIds { get; set; } = new();
    public bool HasUncategorizedExpense { get; set; }
}

public class BusinessTripReportEmployeeDto
{
    public string EmployeeCode { get; set; } = string.Empty;
    public string EmployeeName { get; set; } = string.Empty;
    public string Department { get; set; } = string.Empty;
    public int TotalCases { get; set; }
    public decimal TotalAdvance { get; set; }
    public decimal TotalSettled { get; set; }
    public decimal TotalBalance { get; set; }
    public int PendingAdvance { get; set; }
    public int PendingSettlement { get; set; }
    public int ClosedCases { get; set; }
}

public class BusinessTripReportCategoryDto
{
    public Guid? CategoryId { get; set; }
    public string? CategoryCode { get; set; }
    public string CategoryName { get; set; } = string.Empty;
    public int LineCount { get; set; }
    public int CaseCount { get; set; }
    public decimal TotalAmount { get; set; }
    public decimal WithInvoiceAmount { get; set; }
    public decimal WithoutInvoiceAmount { get; set; }
    public decimal Percentage { get; set; }
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

public class CashReportListDto
{
    public List<CashReportItemDto> Items { get; set; } = new();
    /// <summary>Phiếu chờ thu/chi ngoài kỳ lọc ngày (để sổ quỹ đầy đủ).</summary>
    public List<CashReportItemDto> PendingItems { get; set; } = new();
    public int TotalCount { get; set; }
    public int Page { get; set; }
    public int PageSize { get; set; }
    public CashReportSummaryDto Summary { get; set; } = new();
}

public class CashReportSummaryDto
{
    public decimal PaidIncome { get; set; }
    public decimal PaidExpense { get; set; }
    public decimal FundBalance => PaidIncome - PaidExpense;
    public int PaidIncomeCount { get; set; }
    public int PaidExpenseCount { get; set; }
    public decimal PendingIncome { get; set; }
    public decimal PendingExpense { get; set; }
    public int PendingIncomeCount { get; set; }
    public int PendingExpenseCount { get; set; }
    public int CancelledCount { get; set; }
}

public class CashReportItemDto
{
    public Guid Id { get; set; }
    public string TransactionCode { get; set; } = string.Empty;
    public int Type { get; set; }
    public Guid CategoryId { get; set; }
    public string CategoryName { get; set; } = string.Empty;
    public decimal Amount { get; set; }
    public DateTime TransactionDate { get; set; }
    public string Description { get; set; } = string.Empty;
    public int PaymentMethod { get; set; }
    public int Status { get; set; }
    public bool IsPaid { get; set; }
    public string CreatedByUserName { get; set; } = string.Empty;
}


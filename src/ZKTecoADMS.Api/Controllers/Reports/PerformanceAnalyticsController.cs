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
/// Cluster 7 — Performance Analytics:
/// kpi-summary, production-output, asset-assignment.
/// </summary>
[ApiController]
[Route("api/reports/performance")]
[Authorize]
public class PerformanceAnalyticsController(
    ZKTecoDbContext db,
    ILogger<PerformanceAnalyticsController> logger
) : AuthenticatedControllerBase
{
    // ═════════════════════════════════════════════════════════════════════
    // 1. KPI SUMMARY — Tổng hợp KPI theo kỳ
    // GET /api/reports/performance/kpi-summary?periodId=&department=
    // ═════════════════════════════════════════════════════════════════════
    [HttpGet("kpi-summary")]
    [RequireModulePermission("KPI", ModulePermissionAction.View)]
    public async Task<IActionResult> GetKpiSummary(
        [FromQuery] Guid? periodId = null,
        [FromQuery] int? year = null,
        [FromQuery] int? month = null,
        [FromQuery] string? department = null,
        [FromQuery] string? format = null,
        CancellationToken ct = default)
    {
        try
        {
            var storeId = RequiredStoreId;

            // Resolve period
            if (!periodId.HasValue)
            {
                var now = ReportHelpers.NowVn();
                var y = year ?? now.Year;
                var m = month ?? now.Month;
                var period = await db.KpiPeriods.IgnoreQueryFilters()
                    .Where(p => p.StoreId == storeId && p.Year == y && (p.Month == m || p.Month == null))
                    .OrderByDescending(p => p.Month)
                    .FirstOrDefaultAsync(ct);
                if (period == null)
                    return Ok(AppResponse<KpiSummaryReportDto>.Success(new KpiSummaryReportDto { Year = y, Month = m }));
                periodId = period.Id;
            }

            var periodInfo = await db.KpiPeriods.IgnoreQueryFilters()
                .Where(p => p.Id == periodId.Value)
                .Select(p => new { p.Name, p.Year, p.Month, p.Quarter, p.PeriodStart, p.PeriodEnd })
                .FirstOrDefaultAsync(ct);

            var rows = await (from r in db.KpiResults.IgnoreQueryFilters()
                              join e in db.Employees.IgnoreQueryFilters()
                                on r.EmployeeId equals e.Id
                              join c in db.KpiConfigs.IgnoreQueryFilters()
                                on r.KpiConfigId equals c.Id
                              where r.StoreId == storeId && r.KpiPeriodId == periodId.Value
                              select new
                              {
                                  r.EmployeeId, e.EmployeeCode, e.FirstName, e.LastName, e.Department,
                                  KpiCode = c.Code, KpiName = c.Name, c.Weight,
                                  r.ActualValue, r.TargetValue, r.CompletionRate, r.WeightedScore
                              }).ToListAsync(ct);

            if (!string.IsNullOrWhiteSpace(department))
                rows = rows.Where(r => (r.Department ?? "").Contains(department, StringComparison.OrdinalIgnoreCase)).ToList();

            var byEmployee = rows.GroupBy(r => new { r.EmployeeId, r.EmployeeCode, r.FirstName, r.LastName, r.Department })
                .Select(g => new KpiEmployeeItemDto
                {
                    EmployeeCode = g.Key.EmployeeCode,
                    EmployeeName = ReportHelpers.FullName(g.Key.LastName, g.Key.FirstName),
                    Department = g.Key.Department ?? "N/A",
                    KpiCount = g.Count(),
                    AvgCompletion = Math.Round(g.Average(x => (double)x.CompletionRate), 2),
                    TotalScore = Math.Round(g.Sum(x => x.WeightedScore), 2),
                    Details = g.Select(x => new KpiDetailItemDto
                    {
                        Code = x.KpiCode,
                        Name = x.KpiName,
                        Actual = x.ActualValue,
                        Target = x.TargetValue,
                        CompletionPercent = x.CompletionRate,
                        WeightedScore = x.WeightedScore
                    }).ToList()
                })
                .OrderByDescending(i => i.TotalScore)
                .ToList();

            var byDept = rows.GroupBy(r => r.Department ?? "(Chưa phân PB)")
                .Select(g => new KpiDepartmentItemDto
                {
                    Department = g.Key,
                    EmployeeCount = g.Select(x => x.EmployeeId).Distinct().Count(),
                    AvgCompletion = Math.Round(g.Average(x => (double)x.CompletionRate), 2),
                    AvgScore = Math.Round(g.Average(x => (double)x.WeightedScore), 2)
                })
                .OrderByDescending(d => d.AvgScore)
                .ToList();

            var report = new KpiSummaryReportDto
            {
                PeriodId = periodId,
                PeriodName = periodInfo?.Name,
                Year = periodInfo?.Year ?? year ?? 0,
                Month = periodInfo?.Month ?? month,
                PeriodStart = periodInfo?.PeriodStart,
                PeriodEnd = periodInfo?.PeriodEnd,
                TotalEmployees = byEmployee.Count,
                AvgCompletion = byEmployee.Count > 0 ? Math.Round(byEmployee.Average(i => i.AvgCompletion), 2) : 0,
                TopPerformers = byEmployee.Take(10).ToList(),
                ByEmployee = byEmployee,
                ByDepartment = byDept
            };

            if (string.Equals(format, "excel", StringComparison.OrdinalIgnoreCase))
            {
                return ReportHelpers.ExcelFile($"KPI {periodInfo?.Name ?? "period"}",
                    new[] { "Mã NV", "Họ tên", "Phòng ban", "Số KPI", "TB hoàn thành %", "Tổng điểm" },
                    (ws, dataStartRow) => { int row = dataStartRow;
                        foreach (var i in byEmployee)
                        {
                            ws.Cell(row, 1).Value = i.EmployeeCode;
                            ws.Cell(row, 2).Value = i.EmployeeName;
                            ws.Cell(row, 3).Value = i.Department;
                            ws.Cell(row, 4).Value = i.KpiCount;
                            ReportHelpers.PercentCell(ws.Cell(row, 5), i.AvgCompletion);
                            ws.Cell(row, 6).Value = i.TotalScore;
                            row++;
                        }
                    },
                    $"kpi-summary-{periodInfo?.Name ?? "period"}.xlsx", user: User);
            }

            return Ok(AppResponse<KpiSummaryReportDto>.Success(report));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "KPI summary failed");
            return StatusCode(500, AppResponse<KpiSummaryReportDto>.Fail(ex.Message));
        }
    }

    // ═════════════════════════════════════════════════════════════════════
    // 2. PRODUCTION OUTPUT — Sản lượng theo nhân viên / sản phẩm
    // GET /api/reports/performance/production-output?from=&to=&department=&productId=
    // ═════════════════════════════════════════════════════════════════════
    [HttpGet("production-output")]
    [RequireModulePermission("KPI", ModulePermissionAction.View)]
    public async Task<IActionResult> GetProductionOutput(
        [FromQuery] DateTime? from = null,
        [FromQuery] DateTime? to = null,
        [FromQuery] string? department = null,
        [FromQuery] Guid? productId = null,
        [FromQuery] string? format = null,
        CancellationToken ct = default)
    {
        try
        {
            var (_, _, fromUtc, toUtc) = ReportHelpers.VnRange(from, to);
            var storeId = RequiredStoreId;

            var q = db.ProductionEntries.IgnoreQueryFilters()
                .Where(p => p.StoreId == storeId
                    && p.WorkDate >= fromUtc && p.WorkDate < toUtc);
            if (productId.HasValue) q = q.Where(p => p.ProductItemId == productId.Value);

            var rows = await (from p in q
                              join e in db.Employees.IgnoreQueryFilters() on p.EmployeeId equals e.Id
                              join pr in db.ProductItems.IgnoreQueryFilters() on p.ProductItemId equals pr.Id
                              where e.StoreId == storeId
                              select new
                              {
                                  e.EmployeeCode, e.FirstName, e.LastName, e.Department,
                                  pr.Code, pr.Name, pr.Unit,
                                  p.Quantity, p.UnitPrice, p.Amount, p.WorkDate
                              }).ToListAsync(ct);

            if (!string.IsNullOrWhiteSpace(department))
                rows = rows.Where(r => (r.Department ?? "").Contains(department, StringComparison.OrdinalIgnoreCase)).ToList();

            var byEmployee = rows.GroupBy(r => new { r.EmployeeCode, r.FirstName, r.LastName, r.Department })
                .Select(g => new ProductionEmployeeItemDto
                {
                    EmployeeCode = g.Key.EmployeeCode,
                    EmployeeName = ReportHelpers.FullName(g.Key.LastName, g.Key.FirstName),
                    Department = g.Key.Department ?? "N/A",
                    TotalQuantity = g.Sum(x => x.Quantity),
                    TotalAmount = g.Sum(x => x.Amount ?? 0),
                    DaysWorked = g.Select(x => x.WorkDate.Date).Distinct().Count(),
                    AvgDailyQuantity = Math.Round(g.Sum(x => x.Quantity) / Math.Max(1, g.Select(x => x.WorkDate.Date).Distinct().Count()), 2)
                })
                .OrderByDescending(i => i.TotalAmount)
                .ToList();

            var byProduct = rows.GroupBy(r => new { r.Code, r.Name, r.Unit })
                .Select(g => new ProductionProductItemDto
                {
                    ProductCode = g.Key.Code,
                    ProductName = g.Key.Name,
                    Unit = g.Key.Unit ?? "",
                    TotalQuantity = g.Sum(x => x.Quantity),
                    TotalAmount = g.Sum(x => x.Amount ?? 0),
                    EmployeeCount = g.Select(x => x.EmployeeCode).Distinct().Count()
                })
                .OrderByDescending(i => i.TotalAmount)
                .ToList();

            var report = new ProductionOutputReportDto
            {
                From = ReportHelpers.ToVn(fromUtc),
                To = ReportHelpers.ToVn(toUtc.AddTicks(-1)),
                TotalEntries = rows.Count,
                TotalQuantity = rows.Sum(r => r.Quantity),
                TotalAmount = rows.Sum(r => r.Amount ?? 0),
                ByEmployee = byEmployee,
                ByProduct = byProduct
            };

            if (string.Equals(format, "excel", StringComparison.OrdinalIgnoreCase))
            {
                return ReportHelpers.ExcelFile("Sản lượng",
                    new[] { "Mã NV", "Họ tên", "Phòng ban", "Số ngày", "Tổng SL", "TB/ngày", "Tổng tiền" },
                    (ws, dataStartRow) => { int row = dataStartRow;
                        foreach (var i in byEmployee)
                        {
                            ws.Cell(row, 1).Value = i.EmployeeCode;
                            ws.Cell(row, 2).Value = i.EmployeeName;
                            ws.Cell(row, 3).Value = i.Department;
                            ws.Cell(row, 4).Value = i.DaysWorked;
                            ws.Cell(row, 5).Value = i.TotalQuantity;
                            ws.Cell(row, 6).Value = i.AvgDailyQuantity;
                            ReportHelpers.MoneyCell(ws.Cell(row, 7), i.TotalAmount);
                            row++;
                        }
                    },
                    $"production-{report.From:yyyyMMdd}-{report.To:yyyyMMdd}.xlsx", user: User);
            }

            return Ok(AppResponse<ProductionOutputReportDto>.Success(report));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Production output failed");
            return StatusCode(500, AppResponse<ProductionOutputReportDto>.Fail(ex.Message));
        }
    }

    // ═════════════════════════════════════════════════════════════════════
    // 3. ASSET ASSIGNMENT — Tài sản đã cấp phát / hư/mất
    // GET /api/reports/performance/asset-assignment?status=&department=
    // ═════════════════════════════════════════════════════════════════════
    [HttpGet("asset-assignment")]
    [RequireModulePermission("KPI", ModulePermissionAction.View)]
    public async Task<IActionResult> GetAssetAssignment(
        [FromQuery] AssetStatus? status = null,
        [FromQuery] string? department = null,
        [FromQuery] string? format = null,
        CancellationToken ct = default)
    {
        try
        {
            var storeId = RequiredStoreId;

            var q = db.Assets.IgnoreQueryFilters()
                .Where(a => a.StoreId == storeId);
            if (status.HasValue) q = q.Where(a => a.Status == status.Value);

            var rows = await (from a in q
                              join e in db.Employees.IgnoreQueryFilters()
                                on a.CurrentAssigneeId equals e.Id into gj
                              from emp in gj.DefaultIfEmpty()
                              select new
                              {
                                  a.Id, a.AssetCode, a.Name, a.Brand, a.Model, a.SerialNumber,
                                  a.Status, a.Quantity, a.PurchasePrice, a.CurrentValue, a.PurchaseDate, a.AssignedDate,
                                  EmployeeCode = emp != null ? emp.EmployeeCode : null,
                                  FirstName = emp != null ? emp.FirstName : null,
                                  LastName = emp != null ? emp.LastName : null,
                                  Department = emp != null ? emp.Department : null
                              }).ToListAsync(ct);

            if (!string.IsNullOrWhiteSpace(department))
                rows = rows.Where(r => (r.Department ?? "").Contains(department, StringComparison.OrdinalIgnoreCase)).ToList();

            var byStatus = rows.GroupBy(r => r.Status)
                .Select(g => new AssetStatusItemDto
                {
                    Status = g.Key.ToString(),
                    Count = g.Count(),
                    Quantity = g.Sum(x => x.Quantity),
                    TotalValue = g.Sum(x => x.CurrentValue ?? x.PurchasePrice)
                })
                .OrderByDescending(i => i.Count)
                .ToList();

            var assigned = rows.Where(r => r.EmployeeCode != null).Select(r => new AssetAssignmentItemDto
            {
                AssetCode = r.AssetCode,
                AssetName = r.Name,
                Brand = r.Brand ?? "-",
                SerialNumber = r.SerialNumber ?? "-",
                Status = r.Status.ToString(),
                EmployeeCode = r.EmployeeCode!,
                EmployeeName = ReportHelpers.FullName(r.LastName, r.FirstName),
                Department = r.Department ?? "N/A",
                AssignedDate = r.AssignedDate.HasValue ? ReportHelpers.ToVn(r.AssignedDate.Value) : (DateTime?)null,
                CurrentValue = r.CurrentValue ?? r.PurchasePrice
            })
            .OrderBy(i => i.Department).ThenBy(i => i.EmployeeName)
            .ToList();

            var report = new AssetAssignmentReportDto
            {
                TotalAssets = rows.Count,
                AssignedCount = assigned.Count,
                InStockCount = rows.Count(r => r.Status == AssetStatus.InStock),
                BrokenCount = rows.Count(r => r.Status == AssetStatus.Broken),
                LostCount = rows.Count(r => r.Status == AssetStatus.Lost),
                DisposedCount = rows.Count(r => r.Status == AssetStatus.Disposed),
                TotalValue = rows.Sum(r => r.CurrentValue ?? r.PurchasePrice),
                ByStatus = byStatus,
                Assignments = assigned
            };

            if (string.Equals(format, "excel", StringComparison.OrdinalIgnoreCase))
            {
                return ReportHelpers.ExcelFile("Tài sản",
                    new[] { "Mã TS", "Tên", "Hãng", "Serial", "Trạng thái", "Mã NV", "Họ tên", "Phòng ban", "Ngày cấp", "Giá trị" },
                    (ws, dataStartRow) => { int row = dataStartRow;
                        foreach (var i in assigned)
                        {
                            ws.Cell(row, 1).Value = i.AssetCode;
                            ws.Cell(row, 2).Value = i.AssetName;
                            ws.Cell(row, 3).Value = i.Brand;
                            ws.Cell(row, 4).Value = i.SerialNumber;
                            ws.Cell(row, 5).Value = i.Status;
                            ws.Cell(row, 6).Value = i.EmployeeCode;
                            ws.Cell(row, 7).Value = i.EmployeeName;
                            ws.Cell(row, 8).Value = i.Department;
                            if (i.AssignedDate.HasValue) ReportHelpers.DateCell(ws.Cell(row, 9), i.AssignedDate.Value);
                            ReportHelpers.MoneyCell(ws.Cell(row, 10), i.CurrentValue);
                            row++;
                        }
                    },
                    "asset-assignment.xlsx", user: User);
            }

            return Ok(AppResponse<AssetAssignmentReportDto>.Success(report));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Asset assignment failed");
            return StatusCode(500, AppResponse<AssetAssignmentReportDto>.Fail(ex.Message));
        }
    }
}

// ═══════════════════════════ DTOs ═══════════════════════════

public class KpiSummaryReportDto
{
    public Guid? PeriodId { get; set; }
    public string? PeriodName { get; set; }
    public int Year { get; set; }
    public int? Month { get; set; }
    public DateTime? PeriodStart { get; set; }
    public DateTime? PeriodEnd { get; set; }
    public int TotalEmployees { get; set; }
    public double AvgCompletion { get; set; }
    public List<KpiEmployeeItemDto> TopPerformers { get; set; } = new();
    public List<KpiEmployeeItemDto> ByEmployee { get; set; } = new();
    public List<KpiDepartmentItemDto> ByDepartment { get; set; } = new();
}
public class KpiEmployeeItemDto
{
    public string EmployeeCode { get; set; } = string.Empty;
    public string EmployeeName { get; set; } = string.Empty;
    public string Department { get; set; } = string.Empty;
    public int KpiCount { get; set; }
    public double AvgCompletion { get; set; }
    public decimal TotalScore { get; set; }
    public List<KpiDetailItemDto> Details { get; set; } = new();
}
public class KpiDetailItemDto
{
    public string Code { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public decimal Actual { get; set; }
    public decimal Target { get; set; }
    public decimal CompletionPercent { get; set; }
    public decimal WeightedScore { get; set; }
}
public class KpiDepartmentItemDto
{
    public string Department { get; set; } = string.Empty;
    public int EmployeeCount { get; set; }
    public double AvgCompletion { get; set; }
    public double AvgScore { get; set; }
}

public class ProductionOutputReportDto
{
    public DateTime From { get; set; }
    public DateTime To { get; set; }
    public int TotalEntries { get; set; }
    public decimal TotalQuantity { get; set; }
    public decimal TotalAmount { get; set; }
    public List<ProductionEmployeeItemDto> ByEmployee { get; set; } = new();
    public List<ProductionProductItemDto> ByProduct { get; set; } = new();
}
public class ProductionEmployeeItemDto
{
    public string EmployeeCode { get; set; } = string.Empty;
    public string EmployeeName { get; set; } = string.Empty;
    public string Department { get; set; } = string.Empty;
    public decimal TotalQuantity { get; set; }
    public decimal TotalAmount { get; set; }
    public int DaysWorked { get; set; }
    public decimal AvgDailyQuantity { get; set; }
}
public class ProductionProductItemDto
{
    public string ProductCode { get; set; } = string.Empty;
    public string ProductName { get; set; } = string.Empty;
    public string Unit { get; set; } = string.Empty;
    public decimal TotalQuantity { get; set; }
    public decimal TotalAmount { get; set; }
    public int EmployeeCount { get; set; }
}

public class AssetAssignmentReportDto
{
    public int TotalAssets { get; set; }
    public int AssignedCount { get; set; }
    public int InStockCount { get; set; }
    public int BrokenCount { get; set; }
    public int LostCount { get; set; }
    public int DisposedCount { get; set; }
    public decimal TotalValue { get; set; }
    public List<AssetStatusItemDto> ByStatus { get; set; } = new();
    public List<AssetAssignmentItemDto> Assignments { get; set; } = new();
}
public class AssetStatusItemDto
{
    public string Status { get; set; } = string.Empty;
    public int Count { get; set; }
    public int Quantity { get; set; }
    public decimal TotalValue { get; set; }
}
public class AssetAssignmentItemDto
{
    public string AssetCode { get; set; } = string.Empty;
    public string AssetName { get; set; } = string.Empty;
    public string Brand { get; set; } = string.Empty;
    public string SerialNumber { get; set; } = string.Empty;
    public string Status { get; set; } = string.Empty;
    public string EmployeeCode { get; set; } = string.Empty;
    public string EmployeeName { get; set; } = string.Empty;
    public string Department { get; set; } = string.Empty;
    public DateTime? AssignedDate { get; set; }
    public decimal CurrentValue { get; set; }
}


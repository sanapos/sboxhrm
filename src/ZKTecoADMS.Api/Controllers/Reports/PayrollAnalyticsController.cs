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
/// Cluster 5 — Payroll Analytics:
/// cost-by-department, ot-cost-ratio, bonus-allowance, payslip-status-distribution.
/// </summary>
[ApiController]
[Route("api/reports/payroll")]
[Authorize]
public class PayrollAnalyticsController(
    ZKTecoDbContext db,
    ILogger<PayrollAnalyticsController> logger
) : AuthenticatedControllerBase
{
    // ═════════════════════════════════════════════════════════════════════
    // 1. COST BY DEPARTMENT — Chi phí lương theo phòng ban
    // GET /api/reports/payroll/cost-by-department?year=&month=
    // ═════════════════════════════════════════════════════════════════════
    [HttpGet("cost-by-department")]
    [RequireModulePermission("PayrollReport", ModulePermissionAction.View)]
    public async Task<IActionResult> GetCostByDepartment(
        [FromQuery] int? year = null,
        [FromQuery] int? month = null,
        [FromQuery] string? department = null,
        [FromQuery] string? format = null,
        CancellationToken ct = default)
    {
        try
        {
            var now = ReportHelpers.NowVn();
            var y = year ?? now.Year;
            var m = month ?? now.Month;
            var storeId = RequiredStoreId;

            var rows = await (from p in db.Payslips.IgnoreQueryFilters()
                              join e in db.Employees.IgnoreQueryFilters()
                                on p.EmployeeUserId equals e.ApplicationUserId
                              where p.StoreId == storeId && e.StoreId == storeId
                                && p.Year == y && p.Month == m
                                && p.Status != PayslipStatus.Cancelled
                              select new
                              {
                                  e.Department,
                                  p.BaseSalary,
                                  p.OvertimePay,
                                  p.HolidayPay,
                                  p.NightShiftPay,
                                  p.Bonus,
                                  p.Allowances,
                                  p.Deductions,
                                  p.GrossSalary,
                                  p.NetSalary,
                                  p.Tax,
                                  p.SocialInsurance,
                                  p.HealthInsurance,
                                  p.UnemploymentInsurance
                              }).ToListAsync(ct);

            if (!string.IsNullOrWhiteSpace(department))
                rows = rows.Where(r => (r.Department ?? "").Contains(department, StringComparison.OrdinalIgnoreCase)).ToList();

            var items = rows.GroupBy(r => r.Department ?? "(Chưa phân PB)")
                .Select(g => new PayrollCostItemDto
                {
                    Department = g.Key,
                    EmployeeCount = g.Count(),
                    BaseSalary = g.Sum(x => x.BaseSalary),
                    OvertimePay = g.Sum(x => x.OvertimePay ?? 0) + g.Sum(x => x.HolidayPay ?? 0) + g.Sum(x => x.NightShiftPay ?? 0),
                    Bonus = g.Sum(x => x.Bonus ?? 0),
                    Allowances = g.Sum(x => x.Allowances ?? 0),
                    Deductions = g.Sum(x => x.Deductions ?? 0),
                    Insurance = g.Sum(x => (x.SocialInsurance ?? 0) + (x.HealthInsurance ?? 0) + (x.UnemploymentInsurance ?? 0)),
                    Tax = g.Sum(x => x.Tax ?? 0),
                    GrossSalary = g.Sum(x => x.GrossSalary),
                    NetSalary = g.Sum(x => x.NetSalary)
                })
                .OrderByDescending(i => i.GrossSalary)
                .ToList();

            var totalGross = items.Sum(i => i.GrossSalary);
            foreach (var i in items)
                i.GrossPercent = totalGross > 0 ? Math.Round((double)(i.GrossSalary / totalGross) * 100, 2) : 0;

            var report = new PayrollCostReportDto
            {
                Year = y,
                Month = m,
                Items = items,
                TotalEmployees = items.Sum(i => i.EmployeeCount),
                TotalGross = totalGross,
                TotalNet = items.Sum(i => i.NetSalary),
                TotalOvertime = items.Sum(i => i.OvertimePay),
                TotalBonus = items.Sum(i => i.Bonus),
                TotalAllowances = items.Sum(i => i.Allowances),
                TotalInsurance = items.Sum(i => i.Insurance),
                TotalTax = items.Sum(i => i.Tax)
            };

            if (string.Equals(format, "excel", StringComparison.OrdinalIgnoreCase))
            {
                return ReportHelpers.ExcelFile($"Lương {m:D2}-{y}",
                    new[] { "Phòng ban", "Số NV", "Lương CB", "OT+Holiday+Night", "Thưởng", "Phụ cấp", "Khấu trừ", "BH", "Thuế", "Gross", "Net", "% Gross" },
                    (ws, dataStartRow) => { int row = dataStartRow;
                        foreach (var i in items)
                        {
                            ws.Cell(row, 1).Value = i.Department;
                            ws.Cell(row, 2).Value = i.EmployeeCount;
                            ReportHelpers.MoneyCell(ws.Cell(row, 3), i.BaseSalary);
                            ReportHelpers.MoneyCell(ws.Cell(row, 4), i.OvertimePay);
                            ReportHelpers.MoneyCell(ws.Cell(row, 5), i.Bonus);
                            ReportHelpers.MoneyCell(ws.Cell(row, 6), i.Allowances);
                            ReportHelpers.MoneyCell(ws.Cell(row, 7), i.Deductions);
                            ReportHelpers.MoneyCell(ws.Cell(row, 8), i.Insurance);
                            ReportHelpers.MoneyCell(ws.Cell(row, 9), i.Tax);
                            ReportHelpers.MoneyCell(ws.Cell(row, 10), i.GrossSalary);
                            ReportHelpers.MoneyCell(ws.Cell(row, 11), i.NetSalary);
                            ReportHelpers.PercentCell(ws.Cell(row, 12), i.GrossPercent);
                            row++;
                        }
                    },
                    $"payroll-cost-{y}-{m:D2}.xlsx", user: User);
            }

            return Ok(AppResponse<PayrollCostReportDto>.Success(report));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Payroll cost failed");
            return StatusCode(500, AppResponse<PayrollCostReportDto>.Fail(ex.Message));
        }
    }

    // ═════════════════════════════════════════════════════════════════════
    // 2. OT COST RATIO — Tỷ lệ chi phí OT/Base theo tháng
    // GET /api/reports/payroll/ot-cost-ratio?year=
    // ═════════════════════════════════════════════════════════════════════
    [HttpGet("ot-cost-ratio")]
    [RequireModulePermission("PayrollReport", ModulePermissionAction.View)]
    public async Task<IActionResult> GetOtCostRatio(
        [FromQuery] int? year = null,
        [FromQuery] string? department = null,
        [FromQuery] string? format = null,
        CancellationToken ct = default)
    {
        try
        {
            var y = year ?? ReportHelpers.NowVn().Year;
            var storeId = RequiredStoreId;

            var rows = await (from p in db.Payslips.IgnoreQueryFilters()
                              join e in db.Employees.IgnoreQueryFilters()
                                on p.EmployeeUserId equals e.ApplicationUserId
                              where p.StoreId == storeId && e.StoreId == storeId
                                && p.Year == y
                                && p.Status != PayslipStatus.Cancelled
                              select new { p.Month, e.Department, p.BaseSalary, p.OvertimePay, p.HolidayPay, p.NightShiftPay, p.OvertimeUnits })
                              .ToListAsync(ct);

            if (!string.IsNullOrWhiteSpace(department))
                rows = rows.Where(r => (r.Department ?? "").Contains(department, StringComparison.OrdinalIgnoreCase)).ToList();

            var months = new List<OtCostMonthlyDto>();
            for (int m = 1; m <= 12; m++)
            {
                var mr = rows.Where(r => r.Month == m).ToList();
                var baseSum = mr.Sum(r => r.BaseSalary);
                var otSum = mr.Sum(r => (r.OvertimePay ?? 0) + (r.HolidayPay ?? 0) + (r.NightShiftPay ?? 0));
                var otUnits = mr.Sum(r => r.OvertimeUnits ?? 0);
                months.Add(new OtCostMonthlyDto
                {
                    Month = m,
                    BaseSalary = baseSum,
                    OvertimePay = otSum,
                    OvertimeUnits = otUnits,
                    Ratio = baseSum > 0 ? Math.Round((double)(otSum / baseSum) * 100, 2) : 0
                });
            }

            var report = new OtCostReportDto
            {
                Year = y,
                Department = department,
                Items = months,
                TotalBase = months.Sum(m => m.BaseSalary),
                TotalOt = months.Sum(m => m.OvertimePay)
            };
            report.OverallRatio = report.TotalBase > 0
                ? Math.Round((double)(report.TotalOt / report.TotalBase) * 100, 2) : 0;

            if (string.Equals(format, "excel", StringComparison.OrdinalIgnoreCase))
            {
                return ReportHelpers.ExcelFile($"OT ratio {y}",
                    new[] { "Tháng", "Lương CB", "OT Pay", "OT Units", "Tỷ lệ %" },
                    (ws, dataStartRow) => { int row = dataStartRow;
                        foreach (var m in months)
                        {
                            ws.Cell(row, 1).Value = $"{m.Month:D2}/{y}";
                            ReportHelpers.MoneyCell(ws.Cell(row, 2), m.BaseSalary);
                            ReportHelpers.MoneyCell(ws.Cell(row, 3), m.OvertimePay);
                            ws.Cell(row, 4).Value = m.OvertimeUnits;
                            ReportHelpers.PercentCell(ws.Cell(row, 5), m.Ratio);
                            row++;
                        }
                    },
                    $"ot-cost-ratio-{y}.xlsx", user: User);
            }

            return Ok(AppResponse<OtCostReportDto>.Success(report));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "OT ratio failed");
            return StatusCode(500, AppResponse<OtCostReportDto>.Fail(ex.Message));
        }
    }

    // ═════════════════════════════════════════════════════════════════════
    // 3. BONUS & ALLOWANCE — Phân tích thưởng/phụ cấp
    // GET /api/reports/payroll/bonus-allowance?year=&month=
    // ═════════════════════════════════════════════════════════════════════
    [HttpGet("bonus-allowance")]
    [RequireModulePermission("PayrollReport", ModulePermissionAction.View)]
    public async Task<IActionResult> GetBonusAllowance(
        [FromQuery] int? year = null,
        [FromQuery] int? month = null,
        [FromQuery] string? format = null,
        CancellationToken ct = default)
    {
        try
        {
            var now = ReportHelpers.NowVn();
            var y = year ?? now.Year;
            var storeId = RequiredStoreId;

            var q = db.Payslips.IgnoreQueryFilters()
                .Where(p => p.StoreId == storeId && p.Year == y
                    && p.Status != PayslipStatus.Cancelled);
            if (month.HasValue) q = q.Where(p => p.Month == month.Value);

            var rows = await (from p in q
                              join e in db.Employees.IgnoreQueryFilters()
                                on p.EmployeeUserId equals e.ApplicationUserId
                              where e.StoreId == storeId
                              select new
                              {
                                  e.Department, e.EmployeeCode, e.FirstName, e.LastName,
                                  p.Year, p.Month, p.Bonus, p.Allowances, p.Deductions
                              }).ToListAsync(ct);

            var byDept = rows.GroupBy(r => r.Department ?? "(Chưa phân PB)")
                .Select(g => new BonusAllowanceItemDto
                {
                    Department = g.Key,
                    EmployeeCount = g.Select(x => x.EmployeeCode).Distinct().Count(),
                    TotalBonus = g.Sum(x => x.Bonus ?? 0),
                    TotalAllowances = g.Sum(x => x.Allowances ?? 0),
                    TotalDeductions = g.Sum(x => x.Deductions ?? 0),
                    AvgBonus = g.Any() ? Math.Round(g.Average(x => x.Bonus ?? 0), 0) : 0,
                    AvgAllowances = g.Any() ? Math.Round(g.Average(x => x.Allowances ?? 0), 0) : 0
                })
                .OrderByDescending(i => i.TotalBonus + i.TotalAllowances)
                .ToList();

            var report = new BonusAllowanceReportDto
            {
                Year = y,
                Month = month,
                Items = byDept,
                TotalBonus = byDept.Sum(i => i.TotalBonus),
                TotalAllowances = byDept.Sum(i => i.TotalAllowances),
                TotalDeductions = byDept.Sum(i => i.TotalDeductions)
            };

            if (string.Equals(format, "excel", StringComparison.OrdinalIgnoreCase))
            {
                var label = month.HasValue ? $"{month:D2}-{y}" : $"{y}";
                return ReportHelpers.ExcelFile($"Thưởng-phụ cấp {label}",
                    new[] { "Phòng ban", "Số NV", "Tổng thưởng", "Tổng phụ cấp", "Khấu trừ", "TB thưởng", "TB phụ cấp" },
                    (ws, dataStartRow) => { int row = dataStartRow;
                        foreach (var i in byDept)
                        {
                            ws.Cell(row, 1).Value = i.Department;
                            ws.Cell(row, 2).Value = i.EmployeeCount;
                            ReportHelpers.MoneyCell(ws.Cell(row, 3), i.TotalBonus);
                            ReportHelpers.MoneyCell(ws.Cell(row, 4), i.TotalAllowances);
                            ReportHelpers.MoneyCell(ws.Cell(row, 5), i.TotalDeductions);
                            ReportHelpers.MoneyCell(ws.Cell(row, 6), i.AvgBonus);
                            ReportHelpers.MoneyCell(ws.Cell(row, 7), i.AvgAllowances);
                            row++;
                        }
                    },
                    $"bonus-allowance-{label}.xlsx", user: User);
            }

            return Ok(AppResponse<BonusAllowanceReportDto>.Success(report));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Bonus allowance failed");
            return StatusCode(500, AppResponse<BonusAllowanceReportDto>.Fail(ex.Message));
        }
    }

    // ═════════════════════════════════════════════════════════════════════
    // 4. PAYSLIP STATUS DISTRIBUTION — Theo dõi tiến độ duyệt lương
    // GET /api/reports/payroll/status-distribution?year=&month=
    // ═════════════════════════════════════════════════════════════════════
    [HttpGet("status-distribution")]
    [RequireModulePermission("PayrollReport", ModulePermissionAction.View)]
    public async Task<IActionResult> GetPayslipStatus(
        [FromQuery] int? year = null,
        [FromQuery] int? month = null,
        [FromQuery] string? format = null,
        CancellationToken ct = default)
    {
        try
        {
            var now = ReportHelpers.NowVn();
            var y = year ?? now.Year;
            var m = month ?? now.Month;
            var storeId = RequiredStoreId;

            var rows = await db.Payslips.IgnoreQueryFilters()
                .Where(p => p.StoreId == storeId && p.Year == y && p.Month == m)
                .GroupBy(p => p.Status)
                .Select(g => new { Status = g.Key, Count = g.Count(), Gross = g.Sum(x => x.GrossSalary), Net = g.Sum(x => x.NetSalary) })
                .ToListAsync(ct);

            var items = Enum.GetValues<PayslipStatus>()
                .Select(s =>
                {
                    var r = rows.FirstOrDefault(x => x.Status == s);
                    return new PayslipStatusItemDto
                    {
                        Status = s.ToString(),
                        Count = r?.Count ?? 0,
                        TotalGross = r?.Gross ?? 0,
                        TotalNet = r?.Net ?? 0
                    };
                }).ToList();

            var total = items.Sum(i => i.Count);
            foreach (var i in items)
                i.Percent = total > 0 ? Math.Round((double)i.Count / total * 100, 2) : 0;

            var report = new PayslipStatusReportDto
            {
                Year = y,
                Month = m,
                Total = total,
                Items = items
            };

            if (string.Equals(format, "excel", StringComparison.OrdinalIgnoreCase))
            {
                return ReportHelpers.ExcelFile($"Payslip status {m:D2}-{y}",
                    new[] { "Trạng thái", "Số bảng lương", "Gross tổng", "Net tổng", "Tỷ lệ %" },
                    (ws, dataStartRow) => { int row = dataStartRow;
                        foreach (var i in items)
                        {
                            ws.Cell(row, 1).Value = i.Status;
                            ws.Cell(row, 2).Value = i.Count;
                            ReportHelpers.MoneyCell(ws.Cell(row, 3), i.TotalGross);
                            ReportHelpers.MoneyCell(ws.Cell(row, 4), i.TotalNet);
                            ReportHelpers.PercentCell(ws.Cell(row, 5), i.Percent);
                            row++;
                        }
                    },
                    $"payslip-status-{y}-{m:D2}.xlsx", user: User);
            }

            return Ok(AppResponse<PayslipStatusReportDto>.Success(report));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Payslip status failed");
            return StatusCode(500, AppResponse<PayslipStatusReportDto>.Fail(ex.Message));
        }
    }
}

// ═══════════════════════════ DTOs ═══════════════════════════

public class PayrollCostReportDto
{
    public int Year { get; set; }
    public int Month { get; set; }
    public int TotalEmployees { get; set; }
    public decimal TotalGross { get; set; }
    public decimal TotalNet { get; set; }
    public decimal TotalOvertime { get; set; }
    public decimal TotalBonus { get; set; }
    public decimal TotalAllowances { get; set; }
    public decimal TotalInsurance { get; set; }
    public decimal TotalTax { get; set; }
    public List<PayrollCostItemDto> Items { get; set; } = new();
}
public class PayrollCostItemDto
{
    public string Department { get; set; } = string.Empty;
    public int EmployeeCount { get; set; }
    public decimal BaseSalary { get; set; }
    public decimal OvertimePay { get; set; }
    public decimal Bonus { get; set; }
    public decimal Allowances { get; set; }
    public decimal Deductions { get; set; }
    public decimal Insurance { get; set; }
    public decimal Tax { get; set; }
    public decimal GrossSalary { get; set; }
    public decimal NetSalary { get; set; }
    public double GrossPercent { get; set; }
}

public class OtCostReportDto
{
    public int Year { get; set; }
    public string? Department { get; set; }
    public decimal TotalBase { get; set; }
    public decimal TotalOt { get; set; }
    public double OverallRatio { get; set; }
    public List<OtCostMonthlyDto> Items { get; set; } = new();
}
public class OtCostMonthlyDto
{
    public int Month { get; set; }
    public decimal BaseSalary { get; set; }
    public decimal OvertimePay { get; set; }
    public decimal OvertimeUnits { get; set; }
    public double Ratio { get; set; }
}

public class BonusAllowanceReportDto
{
    public int Year { get; set; }
    public int? Month { get; set; }
    public decimal TotalBonus { get; set; }
    public decimal TotalAllowances { get; set; }
    public decimal TotalDeductions { get; set; }
    public List<BonusAllowanceItemDto> Items { get; set; } = new();
}
public class BonusAllowanceItemDto
{
    public string Department { get; set; } = string.Empty;
    public int EmployeeCount { get; set; }
    public decimal TotalBonus { get; set; }
    public decimal TotalAllowances { get; set; }
    public decimal TotalDeductions { get; set; }
    public decimal AvgBonus { get; set; }
    public decimal AvgAllowances { get; set; }
}

public class PayslipStatusReportDto
{
    public int Year { get; set; }
    public int Month { get; set; }
    public int Total { get; set; }
    public List<PayslipStatusItemDto> Items { get; set; } = new();
}
public class PayslipStatusItemDto
{
    public string Status { get; set; } = string.Empty;
    public int Count { get; set; }
    public decimal TotalGross { get; set; }
    public decimal TotalNet { get; set; }
    public double Percent { get; set; }
}


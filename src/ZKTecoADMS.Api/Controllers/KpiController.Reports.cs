using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Services.Kpi;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>KPI: số liệu cho bảng lương + báo cáo phân tích kỳ.</summary>
public partial class KpiController
{
    /// <summary>
    /// Lương KPI đưa vào bảng lương tháng [from, to].
    /// Quy tắc: kỳ KPI được trả trong tháng chứa NGÀY KẾT THÚC kỳ (kỳ quý trả vào tháng cuối quý,
    /// không bị cộng lặp vào cả 3 tháng). Ưu tiên lương đã duyệt, rồi đã tính, cuối cùng ước tính
    /// từ chỉ tiêu (cùng công thức với tab Lương KPI). Chỉ tính phần KPI — không cộng lương cơ bản.
    /// </summary>
    [HttpGet("salary/for-payroll")]
    [RequireModulePermission("KPI", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> GetSalaryForPayroll(
        [FromQuery] DateTime from, [FromQuery] DateTime to)
    {
        var storeId = RequiredStoreId;
        var fromD = from.Date;
        var toD = to.Date.AddDays(1);
        var periods = await dbContext.KpiPeriods.AsNoTracking()
            .Where(p => p.StoreId == storeId && p.Deleted == null &&
                        p.PeriodEnd >= fromD && p.PeriodEnd < toD)
            .Select(p => new { p.Id, p.Name, p.Status })
            .ToListAsync();
        var periodIds = periods.Select(p => p.Id).ToList();
        if (periodIds.Count == 0)
            return Ok(AppResponse<object>.Success(new { periods = Array.Empty<object>(), items = Array.Empty<object>() }));

        var targets = await dbContext.KpiEmployeeTargets.AsNoTracking()
            .Where(t => t.StoreId == storeId && t.Deleted == null && periodIds.Contains(t.KpiPeriodId))
            .ToListAsync();
        var salaries = await dbContext.KpiSalaries.AsNoTracking()
            .Where(s => s.StoreId == storeId && s.Deleted == null && periodIds.Contains(s.KpiPeriodId))
            .ToListAsync();

        var rows = new Dictionary<Guid, (decimal Amount, string Source, decimal Pct, List<string> Periods)>();
        var rank = new Dictionary<string, int> { ["approved"] = 0, ["calculated"] = 1, ["estimate"] = 2 };
        void Add(Guid emp, decimal amount, string source, decimal pct, string period)
        {
            var cur = rows.TryGetValue(emp, out var found)
                ? found
                : (Amount: 0m, Source: "", Pct: 0m, Periods: new List<string>());
            // Nguồn «yếu» nhất quyết định nhãn (còn 1 kỳ ước tính → cả dòng là ước tính).
            var src = cur.Source == "" || rank[source] > rank[cur.Source] ? source : cur.Source;
            cur.Periods.Add(period);
            rows[emp] = (cur.Amount + amount, src, pct, cur.Periods);
        }

        foreach (var period in periods)
        {
            var pTargets = targets.Where(t => t.KpiPeriodId == period.Id).GroupBy(t => t.EmployeeId).ToList();
            var pSalaries = salaries.Where(s => s.KpiPeriodId == period.Id)
                .GroupBy(s => s.EmployeeId)
                .ToDictionary(g => g.Key, g => g.OrderByDescending(x => x.IsApproved).First());

            foreach (var g in pTargets)
            {
                var pays = g.Select(KpiPayCalculator.Compute).ToList();
                var pct = pays.Count > 0 ? Math.Round(pays.Average(x => x.CompletionPct), 1) : 0;
                if (pSalaries.TryGetValue(g.Key, out var sal))
                    Add(g.Key, sal.GrossIncome, sal.IsApproved ? "approved" : "calculated", pct, period.Name);
                else if (g.Any(t => t.ActualValue.HasValue))
                    Add(g.Key, pays.Sum(x => x.Total), "estimate", pct, period.Name);
            }

            // Kỳ tính theo điểm (không có chỉ tiêu NV): chỉ lấy phần thưởng KPI + thưởng khác.
            foreach (var (empId, sal) in pSalaries)
            {
                if (pTargets.Any(g => g.Key == empId)) continue;
                Add(empId, sal.KpiBonusAmount + sal.OtherBonus,
                    sal.IsApproved ? "approved" : "calculated", sal.TotalKpiScore, period.Name);
            }
        }

        var empIds = rows.Keys.ToList();
        var employees = await dbContext.Employees.AsNoTracking()
            .Where(e => empIds.Contains(e.Id))
            .Select(e => new { e.Id, e.EmployeeCode })
            .ToDictionaryAsync(e => e.Id);

        return Ok(AppResponse<object>.Success(new
        {
            periods = periods.Select(p => new { id = p.Id, name = p.Name, status = p.Status }),
            items = rows.Select(kv => new
            {
                employeeId = kv.Key,
                employeeCode = employees.GetValueOrDefault(kv.Key)?.EmployeeCode,
                amount = Math.Round(kv.Value.Amount, 0),
                source = kv.Value.Source,
                completionPct = kv.Value.Pct,
                periods = string.Join(", ", kv.Value.Periods.Distinct()),
            }),
        }));
    }

    /// <summary>
    /// Báo cáo KPI của kỳ: phân bố mức hoàn thành, theo phòng ban, top / cần cải thiện,
    /// tổng lương KPI và so sánh với kỳ trước.
    /// </summary>
    [HttpGet("report")]
    [RequireModulePermission("KPI", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> GetKpiReport([FromQuery] Guid? periodId)
    {
        var storeId = RequiredStoreId;
        var periodsQ = dbContext.KpiPeriods.AsNoTracking().Where(p => p.StoreId == storeId && p.Deleted == null);
        var period = periodId.HasValue
            ? await periodsQ.FirstOrDefaultAsync(p => p.Id == periodId.Value)
            : await periodsQ.OrderByDescending(p => p.PeriodEnd).FirstOrDefaultAsync();
        if (period == null)
            return Ok(AppResponse<object>.Success(new { hasData = false }));

        var previous = await periodsQ
            .Where(p => p.PeriodEnd < period.PeriodStart && p.Frequency == period.Frequency)
            .OrderByDescending(p => p.PeriodEnd)
            .FirstOrDefaultAsync();

        var current = await BuildPeriodRowsAsync(storeId, period.Id);
        var prevRows = previous == null ? [] : await BuildPeriodRowsAsync(storeId, previous.Id);

        static object Summ(List<KpiReportRow> r) => new
        {
            employees = r.Count,
            avgCompletion = r.Count > 0 ? Math.Round(r.Average(x => x.CompletionPct), 1) : 0,
            achieved = r.Count(x => x.CompletionPct >= 100),
            totalPay = r.Sum(x => x.Pay),
        };

        var buckets = new[]
        {
            ("Dưới 50%", 0m, 50m), ("50–80%", 50m, 80m), ("80–100%", 80m, 100m),
            ("100–120%", 100m, 120m), ("Từ 120%", 120m, decimal.MaxValue),
        };

        var managerIds = IsEmployee && !IsManager && EmployeeId.HasValue ? new[] { EmployeeId.Value } : null;
        var visible = managerIds == null ? current : current.Where(r => managerIds.Contains(r.EmployeeId)).ToList();

        return Ok(AppResponse<object>.Success(new
        {
            hasData = current.Count > 0,
            period = new { id = period.Id, name = period.Name, status = period.Status, period.PeriodStart, period.PeriodEnd },
            previousPeriod = previous == null ? null : new { id = previous.Id, name = previous.Name },
            summary = Summ(current),
            previousSummary = previous == null ? null : Summ(prevRows),
            approvedCount = current.Count(r => r.Approved),
            distribution = buckets.Select(b => new
            {
                label = b.Item1,
                count = current.Count(r => r.CompletionPct >= b.Item2 && r.CompletionPct < b.Item3),
            }),
            byDepartment = current
                .GroupBy(r => string.IsNullOrWhiteSpace(r.Department) ? "Chưa phân phòng" : r.Department!)
                .Select(g => new
                {
                    department = g.Key,
                    employees = g.Count(),
                    avgCompletion = Math.Round(g.Average(x => x.CompletionPct), 1),
                    achieved = g.Count(x => x.CompletionPct >= 100),
                    totalPay = g.Sum(x => x.Pay),
                })
                .OrderByDescending(x => x.avgCompletion),
            byCriteria = current.SelectMany(r => r.Criteria)
                .GroupBy(c => c.Criteria)
                .Select(g => new
                {
                    criteria = g.Key,
                    target = g.Sum(x => x.Target),
                    actual = g.Sum(x => x.Actual),
                    completionPct = g.Sum(x => x.Target) > 0
                        ? Math.Round(g.Sum(x => x.Actual) / g.Sum(x => x.Target) * 100m, 1) : 0,
                }),
            top = visible.OrderByDescending(r => r.CompletionPct).Take(5).Select(RowDto),
            needImprovement = visible.Where(r => r.CompletionPct < 100)
                .OrderBy(r => r.CompletionPct).Take(5).Select(RowDto),
            rows = visible.OrderByDescending(r => r.CompletionPct).Select(RowDto),
        }));
    }

    static object RowDto(KpiReportRow r) => new
    {
        employeeId = r.EmployeeId,
        employeeCode = r.EmployeeCode,
        employeeName = r.EmployeeName,
        department = r.Department,
        completionPct = r.CompletionPct,
        pay = r.Pay,
        approved = r.Approved,
    };

    sealed record KpiCriteriaRow(string Criteria, decimal Target, decimal Actual);

    sealed record KpiReportRow(
        Guid EmployeeId, string? EmployeeCode, string EmployeeName, string? Department,
        decimal CompletionPct, decimal Pay, bool Approved, List<KpiCriteriaRow> Criteria);

    /// <summary>Một dòng / nhân viên: ưu tiên chỉ tiêu NV (doanh thu / point), không có thì dùng điểm KPI.</summary>
    async Task<List<KpiReportRow>> BuildPeriodRowsAsync(Guid storeId, Guid periodId)
    {
        var targets = await dbContext.KpiEmployeeTargets.AsNoTracking()
            .Include(t => t.Employee)
            .Where(t => t.StoreId == storeId && t.KpiPeriodId == periodId && t.Deleted == null)
            .ToListAsync();
        var salaries = (await dbContext.KpiSalaries.AsNoTracking()
                .Where(s => s.StoreId == storeId && s.KpiPeriodId == periodId && s.Deleted == null)
                .ToListAsync())
            .GroupBy(s => s.EmployeeId)
            .ToDictionary(g => g.Key, g => g.OrderByDescending(x => x.IsApproved).First());

        var rows = new List<KpiReportRow>();
        foreach (var g in targets.GroupBy(t => t.EmployeeId))
        {
            var emp = g.First().Employee;
            var pays = g.Select(KpiPayCalculator.Compute).ToList();
            salaries.TryGetValue(g.Key, out var sal);
            rows.Add(new KpiReportRow(
                g.Key, emp.EmployeeCode, $"{emp.LastName} {emp.FirstName}".Trim(), emp.Department,
                Math.Round(pays.Average(x => x.CompletionPct), 1),
                sal?.GrossIncome ?? pays.Sum(x => x.Total),
                sal?.IsApproved == true,
                g.Select(t => new KpiCriteriaRow(
                    t.CriteriaType == 1 ? "Point" : "Doanh thu", t.TargetValue, t.ActualValue ?? 0)).ToList()));
        }

        if (rows.Count > 0) return rows;

        // Kỳ đánh giá theo điểm (KpiResult + trọng số).
        var results = await dbContext.KpiResults.AsNoTracking()
            .Include(r => r.Employee)
            .Include(r => r.KpiConfig)
            .Where(r => r.StoreId == storeId && r.KpiPeriodId == periodId && r.Deleted == null)
            .ToListAsync();
        foreach (var g in results.GroupBy(r => r.EmployeeId))
        {
            var emp = g.First().Employee;
            salaries.TryGetValue(g.Key, out var sal);
            rows.Add(new KpiReportRow(
                g.Key, emp.EmployeeCode, $"{emp.LastName} {emp.FirstName}".Trim(), emp.Department,
                Math.Round(g.Sum(r => r.WeightedScore), 1),
                sal == null ? 0 : sal.KpiBonusAmount + sal.OtherBonus,
                sal?.IsApproved == true,
                g.Select(r => new KpiCriteriaRow(r.KpiConfig.Name, r.TargetValue, r.ActualValue)).ToList()));
        }
        return rows;
    }
}

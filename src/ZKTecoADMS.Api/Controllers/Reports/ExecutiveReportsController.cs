using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers.Reports;

/// <summary>
/// Cluster 8 — Executive Dashboard:
/// monthly-summary (one-page KPI cho CEO/HR Director).
/// </summary>
[ApiController]
[Route("api/reports/executive")]
[Authorize]
public class ExecutiveReportsController(
    ZKTecoDbContext db,
    ILogger<ExecutiveReportsController> logger
) : AuthenticatedControllerBase
{
    // ═════════════════════════════════════════════════════════════════════
    // MONTHLY SUMMARY — Bản tổng hợp điều hành 1 trang cho 1 tháng
    // GET /api/reports/executive/monthly-summary?year=&month=&format=excel
    // ═════════════════════════════════════════════════════════════════════
    [HttpGet("monthly-summary")]
    public async Task<IActionResult> GetMonthlySummary(
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
            var (_, _, fromUtc, toUtc) = ReportHelpers.VnMonthRange(y, m);
            var monthStart = new DateTime(y, m, 1);
            var monthEnd = monthStart.AddMonths(1);

            // ── A. Headcount ─────────────────────────────────────────────
            var emps = await db.Employees.IgnoreQueryFilters()
                .Where(e => e.StoreId == storeId)
                .Select(e => new { e.Id, e.JoinDate, e.ResignationDate, e.CreatedAt, e.Deleted, e.WorkStatus, e.Department, e.DateOfBirth })
                .ToListAsync(ct);

            var headStart = emps.Count(e => (e.JoinDate ?? e.CreatedAt) < monthStart
                && !((e.ResignationDate.HasValue && e.ResignationDate < monthStart)
                    || (e.Deleted.HasValue && e.Deleted < monthStart)));
            var headEnd = emps.Count(e => (e.JoinDate ?? e.CreatedAt) < monthEnd
                && !((e.ResignationDate.HasValue && e.ResignationDate < monthEnd)
                    || (e.Deleted.HasValue && e.Deleted < monthEnd)));
            var hired = emps.Count(e => (e.JoinDate ?? e.CreatedAt).Date >= monthStart
                && (e.JoinDate ?? e.CreatedAt).Date < monthEnd);
            var resigned = emps.Count(e =>
                (e.ResignationDate.HasValue && e.ResignationDate.Value.Date >= monthStart && e.ResignationDate.Value.Date < monthEnd)
                || (e.Deleted.HasValue && e.Deleted.Value.Date >= monthStart && e.Deleted.Value.Date < monthEnd));
            var turnoverRate = (headStart + headEnd) > 0
                ? Math.Round(resigned / ((headStart + headEnd) / 2.0) * 100, 2) : 0;

            // ── B. Attendance ────────────────────────────────────────────
            var punches = await db.AttendanceLogs.IgnoreQueryFilters()
                .Where(a => a.Device != null && a.Device.StoreId == storeId
                    && a.AttendanceTime >= fromUtc && a.AttendanceTime < toUtc)
                .Select(a => new { a.PIN, a.AttendanceTime })
                .ToListAsync(ct);
            var uniqueDays = punches
                .GroupBy(p => new { p.PIN, Day = ReportHelpers.ToVn(p.AttendanceTime).Date })
                .Count();
            var totalPunches = punches.Count;

            // ── C. Leave ─────────────────────────────────────────────────
            var leaves = await db.Leaves.IgnoreQueryFilters()
                .Where(l => l.StoreId == storeId
                    && l.StartDate < toUtc && l.EndDate >= fromUtc)
                .Select(l => new { l.Status, l.Type, l.StartDate, l.EndDate })
                .ToListAsync(ct);
            var approvedLeaves = leaves.Count(l => l.Status == LeaveStatus.Approved);
            var pendingLeaves = leaves.Count(l => l.Status == LeaveStatus.Pending);

            // ── D. Payroll ───────────────────────────────────────────────
            var payroll = await (from p in db.Payslips.IgnoreQueryFilters()
                                 where p.StoreId == storeId && p.Year == y && p.Month == m
                                    && p.Status != PayslipStatus.Cancelled
                                 select new { p.GrossSalary, p.NetSalary, p.BaseSalary,
                                     OtSum = (p.OvertimePay ?? 0) + (p.HolidayPay ?? 0) + (p.NightShiftPay ?? 0),
                                     p.Bonus, p.Allowances, p.Tax,
                                     Ins = (p.SocialInsurance ?? 0) + (p.HealthInsurance ?? 0) + (p.UnemploymentInsurance ?? 0),
                                     p.Status })
                                 .ToListAsync(ct);
            var totalGross = payroll.Sum(p => p.GrossSalary);
            var totalNet = payroll.Sum(p => p.NetSalary);
            var totalOt = payroll.Sum(p => p.OtSum);
            var totalBonus = payroll.Sum(p => p.Bonus ?? 0);

            // ── E. Penalty / Advance / Meal ──────────────────────────────
            var penalty = await db.PenaltyTickets.IgnoreQueryFilters()
                .Where(t => t.StoreId == storeId
                    && t.ViolationDate >= fromUtc && t.ViolationDate < toUtc)
                .Select(t => new { t.Amount, t.Status })
                .ToListAsync(ct);
            var penaltyTotal = penalty.Where(p => p.Status == PenaltyTicketStatus.Approved
                    || p.Status == PenaltyTicketStatus.AutoApproved).Sum(p => p.Amount);

            var advance = await db.AdvanceRequests.IgnoreQueryFilters()
                .Where(a => a.StoreId == storeId
                    && a.RequestDate >= fromUtc && a.RequestDate < toUtc)
                .Select(a => new { a.Amount, a.Status, a.IsPaid })
                .ToListAsync(ct);
            var advanceApproved = advance.Where(a => a.Status == AdvanceRequestStatus.Approved).Sum(a => a.Amount);
            var advanceOutstanding = advance.Where(a => a.Status == AdvanceRequestStatus.Approved && !a.IsPaid).Sum(a => a.Amount);

            var mealPeriod = $"{y:D4}-{m:D2}";
            var meals = await db.MealDebts.IgnoreQueryFilters()
                .Where(md => md.StoreId == storeId && md.Period == mealPeriod)
                .Select(md => new { md.Type, md.Amount })
                .ToListAsync(ct);
            var mealCharge = meals.Where(x => x.Type == 0).Sum(x => x.Amount);
            var mealPayment = meals.Where(x => x.Type == 1).Sum(x => x.Amount);
            var mealOutstanding = mealCharge - mealPayment;

            // ── Compose ──────────────────────────────────────────────────
            var report = new ExecutiveSummaryDto
            {
                Year = y,
                Month = m,
                Headcount = new HeadcountBlock
                {
                    AtMonthStart = headStart,
                    AtMonthEnd = headEnd,
                    Hired = hired,
                    Resigned = resigned,
                    NetChange = hired - resigned,
                    TurnoverRatePercent = turnoverRate
                },
                Attendance = new AttendanceBlock
                {
                    TotalPunches = totalPunches,
                    UniqueManDays = uniqueDays,
                    AvgPunchesPerDay = uniqueDays > 0 ? Math.Round((double)totalPunches / uniqueDays, 2) : 0
                },
                Leave = new LeaveBlock
                {
                    ApprovedLeaves = approvedLeaves,
                    PendingLeaves = pendingLeaves
                },
                Payroll = new PayrollBlock
                {
                    PayslipCount = payroll.Count,
                    TotalGross = totalGross,
                    TotalNet = totalNet,
                    TotalOvertime = totalOt,
                    TotalBonus = totalBonus,
                    OtRatioPercent = payroll.Sum(p => p.BaseSalary) > 0
                        ? Math.Round((double)(totalOt / payroll.Sum(p => p.BaseSalary)) * 100, 2) : 0
                },
                Finance = new FinanceBlock
                {
                    PenaltyApproved = penaltyTotal,
                    AdvanceApproved = advanceApproved,
                    AdvanceOutstanding = advanceOutstanding,
                    MealCharge = mealCharge,
                    MealPayment = mealPayment,
                    MealOutstanding = mealOutstanding
                }
            };

            if (string.Equals(format, "excel", StringComparison.OrdinalIgnoreCase))
            {
                return BuildExecutiveExcel(report);
            }

            return Ok(AppResponse<ExecutiveSummaryDto>.Success(report));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Executive summary failed");
            return StatusCode(500, AppResponse<ExecutiveSummaryDto>.Fail(ex.Message));
        }
    }

    private static IActionResult BuildExecutiveExcel(ExecutiveSummaryDto r)
    {
        return ReportHelpers.ExcelFile($"Tổng hợp {r.Month:D2}-{r.Year}",
            new[] { "Chỉ số", "Giá trị" },
            ws =>
            {
                int row = 2;
                void AddSection(string title)
                {
                    ws.Cell(row, 1).Value = title;
                    ws.Cell(row, 1).Style.Font.Bold = true;
                    ws.Cell(row, 1).Style.Fill.BackgroundColor = ClosedXML.Excel.XLColor.LightGray;
                    ws.Range(row, 1, row, 2).Merge();
                    row++;
                }
                void AddRow(string label, object value, bool isMoney = false, bool isPercent = false)
                {
                    ws.Cell(row, 1).Value = label;
                    if (isMoney && value is decimal d)
                        ReportHelpers.MoneyCell(ws.Cell(row, 2), d);
                    else if (isPercent && value is double p)
                        ReportHelpers.PercentCell(ws.Cell(row, 2), p);
                    else
                        ws.Cell(row, 2).Value = value?.ToString() ?? "";
                    row++;
                }

                AddSection($"Kỳ: Tháng {r.Month:D2}/{r.Year}");
                AddSection("A. Nhân sự (Headcount)");
                AddRow("HC đầu tháng", r.Headcount.AtMonthStart);
                AddRow("HC cuối tháng", r.Headcount.AtMonthEnd);
                AddRow("Tuyển mới", r.Headcount.Hired);
                AddRow("Nghỉ việc", r.Headcount.Resigned);
                AddRow("Net change", r.Headcount.NetChange);
                AddRow("Turnover %", r.Headcount.TurnoverRatePercent, isPercent: true);

                AddSection("B. Chấm công");
                AddRow("Tổng lượt chấm", r.Attendance.TotalPunches);
                AddRow("Ngày công (man-days)", r.Attendance.UniqueManDays);
                AddRow("TB lượt/ngày", r.Attendance.AvgPunchesPerDay);

                AddSection("C. Nghỉ phép");
                AddRow("Đơn đã duyệt", r.Leave.ApprovedLeaves);
                AddRow("Đơn chờ duyệt", r.Leave.PendingLeaves);

                AddSection("D. Lương");
                AddRow("Số bảng lương", r.Payroll.PayslipCount);
                AddRow("Tổng Gross", r.Payroll.TotalGross, isMoney: true);
                AddRow("Tổng Net", r.Payroll.TotalNet, isMoney: true);
                AddRow("Tổng OT/Holiday/Night", r.Payroll.TotalOvertime, isMoney: true);
                AddRow("Tổng thưởng", r.Payroll.TotalBonus, isMoney: true);
                AddRow("Tỷ lệ OT/Base %", r.Payroll.OtRatioPercent, isPercent: true);

                AddSection("E. Công nợ / Tài chính");
                AddRow("Phạt đã duyệt", r.Finance.PenaltyApproved, isMoney: true);
                AddRow("Ứng lương đã duyệt", r.Finance.AdvanceApproved, isMoney: true);
                AddRow("Ứng lương chưa trả", r.Finance.AdvanceOutstanding, isMoney: true);
                AddRow("Tiền ăn phát sinh", r.Finance.MealCharge, isMoney: true);
                AddRow("Tiền ăn đã thu", r.Finance.MealPayment, isMoney: true);
                AddRow("Tiền ăn còn nợ", r.Finance.MealOutstanding, isMoney: true);

                ws.Columns().AdjustToContents();
            },
            $"executive-summary-{r.Year}-{r.Month:D2}.xlsx");
    }
}

// ═══════════════════════════ DTOs ═══════════════════════════

public class ExecutiveSummaryDto
{
    public int Year { get; set; }
    public int Month { get; set; }
    public HeadcountBlock Headcount { get; set; } = new();
    public AttendanceBlock Attendance { get; set; } = new();
    public LeaveBlock Leave { get; set; } = new();
    public PayrollBlock Payroll { get; set; } = new();
    public FinanceBlock Finance { get; set; } = new();
}
public class HeadcountBlock
{
    public int AtMonthStart { get; set; }
    public int AtMonthEnd { get; set; }
    public int Hired { get; set; }
    public int Resigned { get; set; }
    public int NetChange { get; set; }
    public double TurnoverRatePercent { get; set; }
}
public class AttendanceBlock
{
    public int TotalPunches { get; set; }
    public int UniqueManDays { get; set; }
    public double AvgPunchesPerDay { get; set; }
}
public class LeaveBlock
{
    public int ApprovedLeaves { get; set; }
    public int PendingLeaves { get; set; }
}
public class PayrollBlock
{
    public int PayslipCount { get; set; }
    public decimal TotalGross { get; set; }
    public decimal TotalNet { get; set; }
    public decimal TotalOvertime { get; set; }
    public decimal TotalBonus { get; set; }
    public double OtRatioPercent { get; set; }
}
public class FinanceBlock
{
    public decimal PenaltyApproved { get; set; }
    public decimal AdvanceApproved { get; set; }
    public decimal AdvanceOutstanding { get; set; }
    public decimal MealCharge { get; set; }
    public decimal MealPayment { get; set; }
    public decimal MealOutstanding { get; set; }
}

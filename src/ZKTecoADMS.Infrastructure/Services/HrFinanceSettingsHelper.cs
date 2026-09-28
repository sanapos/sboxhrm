using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Services;

/// <summary>Đọc cài đặt tài chính nhân sự + tính hạn mức ứng lương.</summary>
public static class HrFinanceSettingsHelper
{
    public const int WorkDaysPerMonth = 26;
    public const int HoursPerDay = 8;

    /// <summary>Cài đặt của cửa hàng; chưa có thì trả về mặc định (không lưu).</summary>
    public static async Task<HrFinanceSettings> GetAsync(ZKTecoDbContext db, Guid storeId, CancellationToken ct = default)
    {
        var s = await db.HrFinanceSettings.IgnoreQueryFilters().AsNoTracking()
            .Where(x => x.StoreId == storeId && x.Deleted == null)
            .OrderByDescending(x => x.CreatedAt)
            .FirstOrDefaultAsync(ct);
        return s ?? new HrFinanceSettings { Id = Guid.Empty, StoreId = storeId };
    }

    /// <summary>Lương tháng ước tính từ chế độ lương đang hiệu lực của nhân viên (null nếu chưa gán).</summary>
    public static async Task<decimal?> EstimateMonthlySalaryAsync(
        ZKTecoDbContext db, Guid employeeId, DateTime asOf, CancellationToken ct = default)
    {
        var eb = await db.EmployeeBenefits.IgnoreQueryFilters().AsNoTracking()
            .Include(x => x.Benefit)
            .Where(x => x.EmployeeId == employeeId
                && x.EffectiveDate <= asOf
                && (x.EndDate == null || x.EndDate >= asOf))
            .OrderByDescending(x => x.EffectiveDate)
            .FirstOrDefaultAsync(ct);
        if (eb?.Benefit == null) return null;
        return MonthlyFromRate(eb.Benefit.RateType.ToString(), eb.Benefit.Rate);
    }

    public static decimal MonthlyFromRate(string rateType, decimal rate) => rateType switch
    {
        "Monthly" => rate,
        "Daily" or "Shift" => rate * WorkDaysPerMonth,
        "Hourly" => rate * HoursPerDay * WorkDaysPerMonth,
        _ => rate,
    };

    /// <summary>Hạn mức ứng mỗi kỳ = min(% × lương tháng ước tính, số tiền tối đa). null = không giới hạn.</summary>
    public static decimal? AdvanceLimit(HrFinanceSettings s, decimal? monthlySalary)
    {
        decimal? byPercent = s.AdvanceLimitPercent is > 0 && monthlySalary is > 0
            ? Math.Round(monthlySalary.Value * s.AdvanceLimitPercent.Value / 100m, 0)
            : null;
        decimal? byAmount = s.AdvanceLimitAmount is > 0 ? s.AdvanceLimitAmount : null;
        if (byPercent == null) return byAmount;
        if (byAmount == null) return byPercent;
        return Math.Min(byPercent.Value, byAmount.Value);
    }

    /// <summary>Số tiền ứng lương phải trừ vào kỳ (year, month), tính cả trả góp nhiều kỳ.</summary>
    public static decimal AdvanceDeductionForPeriod(AdvanceRequest a, int year, int month)
    {
        // InstallmentCount = 0: yêu cầu cũ (trước v2) → trừ 1 lần vào tháng chi tiền như trước
        var legacy = a.InstallmentCount <= 0;
        var start = !legacy && a.ForYear.HasValue && a.ForMonth is >= 1 and <= 12
            ? new DateTime(a.ForYear.Value, a.ForMonth.Value, 1)
            : a.PaidDate.HasValue
                ? new DateTime(a.PaidDate.Value.Year, a.PaidDate.Value.Month, 1)
                : new DateTime(a.RequestDate.Year, a.RequestDate.Month, 1);
        var n = Math.Max(1, a.InstallmentCount);
        var target = new DateTime(year, month, 1);
        var idx = (target.Year - start.Year) * 12 + target.Month - start.Month;
        if (idx < 0 || idx >= n) return 0;
        var total = a.ApprovedAmount ?? a.Amount;
        var per = Math.Floor(total / n);
        return idx == n - 1 ? total - per * (n - 1) : per;
    }
}

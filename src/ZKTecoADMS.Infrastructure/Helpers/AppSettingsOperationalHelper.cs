using Microsoft.EntityFrameworkCore;

namespace ZKTecoADMS.Infrastructure.Helpers;

/// <summary>
/// Đọc thiết lập vận hành HRM từ bảng AppSettings theo cửa hàng.
/// </summary>
public static class AppSettingsOperationalHelper
{
    public const string DayEndTimeKey = "day_end_time";
    public const string RoundingRuleKey = "rounding_rule";
    public const string PayrollCutoffDayKey = "payroll_cutoff_day";

    public static async Task<TimeSpan?> ResolveDayEndTimeAsync(
        ZKTecoDbContext db,
        Guid storeId,
        string? overnightCutoffFromQuery = null,
        CancellationToken ct = default)
    {
        if (!string.IsNullOrWhiteSpace(overnightCutoffFromQuery) &&
            TimeSpan.TryParse(overnightCutoffFromQuery, out var fromQuery))
        {
            return fromQuery;
        }

        var setting = await db.AppSettings
            .AsNoTracking()
            .FirstOrDefaultAsync(s => s.StoreId == storeId && s.Key == DayEndTimeKey, ct);

        if (setting?.Value != null && TimeSpan.TryParse(setting.Value, out var parsed))
            return parsed;

        return null;
    }

    public static async Task<string> GetRoundingRuleAsync(
        ZKTecoDbContext db,
        Guid storeId,
        CancellationToken ct = default)
    {
        var setting = await db.AppSettings
            .AsNoTracking()
            .FirstOrDefaultAsync(s => s.StoreId == storeId && s.Key == RoundingRuleKey, ct);

        return string.IsNullOrWhiteSpace(setting?.Value)
            ? "none"
            : setting.Value.Trim().ToLowerInvariant();
    }

    public static async Task<int> GetPayrollCutoffDayAsync(
        ZKTecoDbContext db,
        Guid storeId,
        CancellationToken ct = default)
    {
        var setting = await db.AppSettings
            .AsNoTracking()
            .FirstOrDefaultAsync(s => s.StoreId == storeId && s.Key == PayrollCutoffDayKey, ct);

        if (setting?.Value != null &&
            int.TryParse(setting.Value, out var day) &&
            day >= 1 &&
            day <= 31)
        {
            return day;
        }

        return 25;
    }
}

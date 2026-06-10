using System.Text.Json;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Application.Helpers;

public sealed class StaffingDailyQuotaDto
{
    public int DayOfWeek { get; set; }
    public int MinEmployees { get; set; }
    public int MaxEmployees { get; set; }
}

public static class StaffingQuotaResolver
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true
    };

    public static List<StaffingDailyQuotaDto> ParseDailyQuotas(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return [];
        try
        {
            return JsonSerializer.Deserialize<List<StaffingDailyQuotaDto>>(json, JsonOptions) ?? [];
        }
        catch
        {
            return [];
        }
    }

    public static string? SerializeDailyQuotas(IEnumerable<StaffingDailyQuotaDto>? daily)
    {
        if (daily == null) return null;
        var list = daily
            .Where(d => d.DayOfWeek is >= 1 and <= 7)
            .Select(d => new StaffingDailyQuotaDto
            {
                DayOfWeek = d.DayOfWeek,
                MinEmployees = Math.Max(0, d.MinEmployees),
                MaxEmployees = Math.Max(0, d.MaxEmployees),
            })
            .ToList();
        return list.Count == 0 ? null : JsonSerializer.Serialize(list, JsonOptions);
    }

    /// <summary>1=Monday … 7=Sunday (ISO, khớp Flutter DateTime.weekday).</summary>
    public static int ToIsoWeekday(DateTime date) =>
        date.DayOfWeek == DayOfWeek.Sunday ? 7 : (int)date.DayOfWeek;

    public static (int Min, int Max) ResolveLimitsForDate(ShiftStaffingQuota quota, DateTime date)
    {
        var iso = ToIsoWeekday(date);
        var daily = ParseDailyQuotas(quota.DailyQuotasJson);
        var match = daily.FirstOrDefault(d => d.DayOfWeek == iso);
        if (match != null)
            return (Math.Max(0, match.MinEmployees), Math.Max(0, match.MaxEmployees));

        return (Math.Max(0, quota.MinEmployees), Math.Max(0, quota.MaxEmployees));
    }

    public static ShiftStaffingQuota? PickQuotaForDepartment(
        IReadOnlyList<ShiftStaffingQuota> quotas,
        string? department)
    {
        if (quotas.Count == 0) return null;

        if (!string.IsNullOrWhiteSpace(department))
        {
            var dept = quotas.FirstOrDefault(q =>
                !string.IsNullOrWhiteSpace(q.Department)
                && string.Equals(q.Department, department, StringComparison.OrdinalIgnoreCase));
            if (dept != null) return dept;
        }

        return quotas.FirstOrDefault(q => string.IsNullOrWhiteSpace(q.Department));
    }
}

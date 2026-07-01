namespace ZKTecoADMS.Application.Constants;

/// <summary>
/// Canonical notification category codes and aliases used when persisting preferences
/// or checking whether a user opted out of a category.
/// </summary>
public static class NotificationCategoryCodes
{
    public static readonly HashSet<string> AttendanceGroup = new(StringComparer.OrdinalIgnoreCase)
    {
        "attendance", "device"
    };

    /// <summary>
    /// Maps legacy or module-specific codes to a seeded <see cref="Domain.Entities.NotificationCategory"/> code.
    /// </summary>
    public static string? Normalize(string? code)
    {
        if (string.IsNullOrWhiteSpace(code)) return null;

        return code.Trim().ToLowerInvariant() switch
        {
            "communication" => "internal_comm",
            "salary" => "payroll",
            "employee" => "hr",
            "transaction" => "payroll",
            "mobile_attendance" => "attendance",
            "penalty" => "approval",
            "allowance" => "payroll",
            "meal" => "system",
            "department" => "hr",
            "account" => "hr",
            "store" => "system",
            "license" => "system",
            "shift" => "attendance",
            "pos" => "pos",
            "possaleorder" => "pos",
            "posproduct" => "pos",
            "pospurchasereceipt" => "pos",
            _ => code.Trim().ToLowerInvariant()
        };
    }

    public static bool IsAttendanceGroup(string? code)
    {
        var normalized = Normalize(code);
        return normalized != null && AttendanceGroup.Contains(normalized);
    }
}

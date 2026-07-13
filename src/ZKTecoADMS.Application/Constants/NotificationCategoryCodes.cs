namespace ZKTecoADMS.Application.Constants;

/// <summary>
/// Canonical notification category codes and aliases used when persisting preferences
/// or checking whether a user opted out of a category.
/// </summary>
public static class NotificationCategoryCodes
{
    public static readonly HashSet<string> AttendanceGroup = new(StringComparer.OrdinalIgnoreCase)
    {
        "attendance", "device", "travel_attendance"
    };

    /// <summary>
    /// Maps legacy or module-specific codes to a seeded <see cref="Domain.Entities.NotificationCategory"/> code.
    /// Không remap transaction/penalty/meal sang payroll/approval/system — làm sai tiêu đề FCM.
    /// </summary>
    public static string? Normalize(string? code)
    {
        if (string.IsNullOrWhiteSpace(code)) return null;

        return code.Trim().ToLowerInvariant() switch
        {
            "communication" => "internal_comm",
            "salary" => "payroll",
            "employee" => "hr",
            "department" => "hr",
            "account" => "hr",
            "mobile_attendance" => "attendance",
            "travel_attendance" => "travel_attendance",
            // Thu chi / phạt / suất ăn / POS / công tác: giữ mã riêng
            "transaction" => "transaction",
            "cashtransaction" => "transaction",
            "penalty" => "penalty",
            "penaltyticket" => "penalty",
            "meal" => "meal",
            "allowance" => "payroll",
            "store" => "system",
            "license" => "system",
            "shift" => "shift",
            "pos" => "pos",
            "possaleorder" => "pos",
            "posproduct" => "pos",
            "pospurchasereceipt" => "pos",
            "business_trip" => "business_trip",
            "businesstrip" => "business_trip",
            "businesstripcase" => "business_trip",
            "businesstripexpense" => "business_trip",
            _ => code.Trim().ToLowerInvariant()
        };
    }

    public static bool IsAttendanceGroup(string? code)
    {
        var normalized = Normalize(code);
        return normalized != null && AttendanceGroup.Contains(normalized);
    }
}

using System.Text.RegularExpressions;

namespace ZKTecoADMS.Application.Helpers;

/// <summary>
/// Marker và parse storeId từ nội dung announcement nhắc gia hạn.
/// Marker: [RENEWAL-{days}D-{storeId:N}]
/// </summary>
public static partial class RenewalNotificationHelper
{
    public const int ReminderThresholdMaxDays = 30;

    public static string BuildMarker(int daysThreshold, Guid storeId) =>
        $"[RENEWAL-{daysThreshold}D-{storeId:N}]";

    public static string StoreContentNeedle(Guid storeId) => $"-{storeId:N}]";

    [GeneratedRegex(@"\[RENEWAL-\d+D-([0-9a-fA-F]{32})\]", RegexOptions.Compiled)]
    private static partial Regex RenewalMarkerRegex();

    public static bool TryParseStoreId(string? content, out Guid storeId)
    {
        storeId = Guid.Empty;
        if (string.IsNullOrWhiteSpace(content)) return false;
        var m = RenewalMarkerRegex().Match(content);
        if (!m.Success) return false;
        return Guid.TryParse(m.Groups[1].Value, out storeId);
    }

    public static int? ComputeDaysLeft(DateTime? expiryDateUtc, DateTime? utcNow = null)
    {
        if (expiryDateUtc == null) return null;
        var now = (utcNow ?? DateTime.UtcNow).Date;
        return (expiryDateUtc.Value.Date - now).Days;
    }

    /// <summary>License còn xa hơn ngưỡng nhắc — ẩn banner renewal cũ.</summary>
    public static bool ShouldSuppressRenewalAlert(DateTime? liveExpiryDateUtc, DateTime? utcNow = null)
    {
        var days = ComputeDaysLeft(liveExpiryDateUtc, utcNow);
        return days > ReminderThresholdMaxDays;
    }
}

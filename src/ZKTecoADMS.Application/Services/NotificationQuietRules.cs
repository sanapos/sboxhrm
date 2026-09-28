namespace ZKTecoADMS.Application.Services;

/// <summary>
/// Giờ yên lặng của thông báo đẩy (giờ Việt Nam). Khoảng có thể qua đêm, VD 22:00 → 07:00.
/// </summary>
public static class NotificationQuietRules
{
    public static int VnMinuteOfDay(DateTime utcNow)
    {
        var vn = utcNow.AddHours(7);
        return vn.Hour * 60 + vn.Minute;
    }

    /// <summary>Phút <paramref name="minute"/> có nằm trong khoảng yên lặng [start, end) không.</summary>
    public static bool IsInQuiet(int minute, int start, int end)
    {
        start = Clamp(start); end = Clamp(end); minute = Clamp(minute);
        if (start == end) return false;           // khoảng rỗng
        return start < end
            ? minute >= start && minute < end     // trong ngày, VD 12:00-13:30
            : minute >= start || minute < end;    // qua đêm, VD 22:00-07:00
    }

    /// <summary>Loại thông báo khẩn — vẫn đổ chuông trong giờ yên lặng nếu người dùng cho phép.</summary>
    public static bool IsUrgent(string? notificationType, string? categoryCode)
        => notificationType is "Error" or "ApprovalRequired" or "Warning"
           || string.Equals(categoryCode, "approval", StringComparison.OrdinalIgnoreCase);

    public static string Format(int minute)
    {
        minute = Clamp(minute);
        return $"{minute / 60:00}:{minute % 60:00}";
    }

    /// <summary>"22:00" → 1320; sai định dạng → null.</summary>
    public static int? Parse(string? hm)
    {
        if (string.IsNullOrWhiteSpace(hm)) return null;
        var parts = hm.Trim().Split(':');
        if (parts.Length < 2 || !int.TryParse(parts[0], out var h) || !int.TryParse(parts[1], out var m)) return null;
        if (h is < 0 or > 23 || m is < 0 or > 59) return null;
        return h * 60 + m;
    }

    private static int Clamp(int m) => ((m % 1440) + 1440) % 1440;
}

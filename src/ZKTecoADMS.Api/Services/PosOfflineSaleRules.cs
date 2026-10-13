using System.Text.Json;
using System.Text.RegularExpressions;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Bán offline (mất mạng): số hóa đơn offline «OFF-000123» cấp trước theo dải cho từng thiết bị,
/// giờ bán thật, cài đặt cửa hàng (ExtraJson «offlineSale»: enabled / maxHours — mặc định TẮT).
/// </summary>
public static partial class PosOfflineSaleRules
{
    public const string Prefix = "OFF-";
    public const int DefaultMaxHours = 8;
    static readonly TimeSpan MaxBackdate = TimeSpan.FromDays(7);

    [GeneratedRegex(@"^OFF-(\d{1,9})$")]
    private static partial Regex NoRegex();

    public static string Format(int seq) => $"{Prefix}{seq:D6}";

    /// <summary>Số offline hợp lệ (OFF-123456) hoặc null.</summary>
    public static string? NormalizeNo(string? no)
    {
        var s = (no ?? "").Trim().ToUpperInvariant();
        return NoRegex().IsMatch(s) ? s : null;
    }

    public static int? SeqOf(string? no)
    {
        var m = NoRegex().Match((no ?? "").Trim().ToUpperInvariant());
        return m.Success && int.TryParse(m.Groups[1].Value, out var v) ? v : null;
    }

    /// <summary>Giờ bán của đơn offline: giờ thật trên máy nếu hợp lý (không ở tương lai, không quá 7 ngày).</summary>
    public static DateTime? ResolveOfflineSaleAt(string? offlineNo, DateTime? offlineAt, DateTime utcNow, bool complete)
    {
        if (!complete || NormalizeNo(offlineNo) == null || offlineAt == null) return null;
        var at = offlineAt.Value.Kind switch
        {
            DateTimeKind.Utc => offlineAt.Value,
            DateTimeKind.Local => offlineAt.Value.ToUniversalTime(),
            _ => DateTime.SpecifyKind(offlineAt.Value, DateTimeKind.Utc),
        };
        if (at > utcNow.AddMinutes(10) || at < utcNow - MaxBackdate) return null;
        return at;
    }

    public static void Stamp(PosSaleOrder order, string? offlineNo, DateTime? offlineAt, string? deviceKey)
    {
        if (offlineNo == null) return;
        order.OfflineNo = offlineNo;
        order.OfflineAt = offlineAt == null
            ? DateTime.UtcNow
            : offlineAt.Value.Kind == DateTimeKind.Utc
                ? offlineAt.Value
                : DateTime.SpecifyKind(offlineAt.Value.ToUniversalTime(), DateTimeKind.Utc);
        var key = (deviceKey ?? "").Trim();
        order.OfflineDeviceKey = key.Length == 0 ? null : key.Length > 128 ? key[..128] : key;
    }

    public record Settings(bool Enabled, int MaxHours);

    /// <summary>Cài đặt bán offline trong ExtraJson của thiết lập bán hàng. Không có / lỗi → TẮT.</summary>
    public static Settings ParseSettings(string? extraJson)
    {
        if (string.IsNullOrWhiteSpace(extraJson)) return new(false, DefaultMaxHours);
        try
        {
            using var doc = JsonDocument.Parse(extraJson);
            if (doc.RootElement.ValueKind != JsonValueKind.Object
                || !doc.RootElement.TryGetProperty("offlineSale", out var o)
                || o.ValueKind != JsonValueKind.Object)
                return new(false, DefaultMaxHours);
            var enabled = o.TryGetProperty("enabled", out var e) && e.ValueKind == JsonValueKind.True;
            var hours = o.TryGetProperty("maxHours", out var h) && h.TryGetInt32(out var hv) ? hv : DefaultMaxHours;
            return new(enabled, Math.Clamp(hours, 1, 72));
        }
        catch (JsonException)
        {
            return new(false, DefaultMaxHours);
        }
    }
}

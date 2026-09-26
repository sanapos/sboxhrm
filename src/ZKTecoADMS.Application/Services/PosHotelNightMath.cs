using System.Text.Json;

namespace ZKTecoADMS.Application.Services;

/// <summary>
/// Quy tắc giờ nhận / trả phòng khách sạn (PosStoreSellSettings.ExtraJson → "hotel").
/// Mặc định: nhận 14:00, trả 12:00; đến trước 05:00 tính đêm trước; đến 05:00–14:00 phụ thu ½ đêm;
/// trả sau 12:00 đến 18:00 phụ thu ½ đêm, sau 18:00 thêm 1 đêm; ân hạn 30 phút.
/// </summary>
public sealed record HotelStayPolicy(
    bool NightMode = true,
    int CheckInMinute = 14 * 60,
    int CheckOutMinute = 12 * 60,
    int LateHalfUntilMinute = 18 * 60,
    int EarlyHalfFromMinute = 5 * 60,
    int GraceMinutes = 30,
    decimal HalfFraction = 0.5m)
{
    public static readonly HotelStayPolicy Default = new();

    public static HotelStayPolicy Parse(string? extraJson)
    {
        if (string.IsNullOrWhiteSpace(extraJson)) return Default;
        try
        {
            using var doc = JsonDocument.Parse(extraJson);
            if (doc.RootElement.ValueKind != JsonValueKind.Object) return Default;
            if (!TryProp(doc.RootElement, "hotel", out var h) || h.ValueKind != JsonValueKind.Object)
                return Default;
            var d = Default;
            return new HotelStayPolicy(
                NightMode: TryProp(h, "nightMode", out var nm) && nm.ValueKind == JsonValueKind.False ? false : d.NightMode,
                CheckInMinute: Time(h, "checkIn", d.CheckInMinute),
                CheckOutMinute: Time(h, "checkOut", d.CheckOutMinute),
                LateHalfUntilMinute: Time(h, "lateHalfUntil", d.LateHalfUntilMinute),
                EarlyHalfFromMinute: Time(h, "earlyHalfFrom", d.EarlyHalfFromMinute),
                GraceMinutes: TryProp(h, "graceMinutes", out var g) && g.TryGetInt32(out var gi) && gi >= 0 ? gi : d.GraceMinutes,
                HalfFraction: TryProp(h, "halfFraction", out var f) && f.TryGetDecimal(out var fd) && fd is > 0 and <= 1 ? fd : d.HalfFraction);
        }
        catch (JsonException)
        {
            return Default;
        }
    }

    static bool TryProp(JsonElement e, string name, out JsonElement value)
    {
        foreach (var p in e.EnumerateObject())
            if (string.Equals(p.Name, name, StringComparison.OrdinalIgnoreCase))
            {
                value = p.Value;
                return true;
            }
        value = default;
        return false;
    }

    /// <summary>"14:00" → 840 phút.</summary>
    static int Time(JsonElement h, string name, int fallback) =>
        TryProp(h, name, out var v) && v.ValueKind == JsonValueKind.String
            && TimeSpan.TryParse(v.GetString(), out var ts) && ts >= TimeSpan.Zero && ts < TimeSpan.FromDays(1)
            ? (int)ts.TotalMinutes
            : fallback;
}

public static class PosHotelNightMath
{
    /// <summary>Giờ Việt Nam cho quy tắc nhận / trả phòng.</summary>
    static readonly TimeSpan Vn = TimeSpan.FromHours(7);

    /// <summary>
    /// Số đêm tính tiền (có thể lẻ ½) cho lưu trú từ <paramref name="startUtc"/> đến <paramref name="endUtc"/>.
    /// Đêm thứ k (k ≥ 2) chỉ tính khi khách ở quá giờ «trả muộn ½» của ngày đó; phần vượt giờ trả
    /// (quá ân hạn) trước mốc đó tính ½ đêm; đến sớm 05:00–giờ nhận tính thêm ½ đêm.
    /// </summary>
    public static decimal Nights(DateTime startUtc, DateTime endUtc, HotelStayPolicy? policy = null)
    {
        var p = policy ?? HotelStayPolicy.Default;
        var start = PosServiceBillingMath.AsUtc(startUtc) + Vn;
        var end = PosServiceBillingMath.AsUtc(endUtc) + Vn;
        if (end <= start) end = start;
        var grace = TimeSpan.FromMinutes(p.GraceMinutes);
        var startMin = (int)start.TimeOfDay.TotalMinutes;

        // Đến trước giờ «sớm ½» (vd 01:00) → thuộc đêm hôm trước.
        var anchor = startMin < p.EarlyHalfFromMinute ? start.Date.AddDays(-1) : start.Date;
        var extra = 0m;
        if (startMin >= p.EarlyHalfFromMinute && startMin < p.CheckInMinute - p.GraceMinutes)
            extra += p.HalfFraction;

        var nights = 1;
        while (end > anchor.AddDays(nights).AddMinutes(p.LateHalfUntilMinute))
            nights++;

        var checkout = anchor.AddDays(nights).AddMinutes(p.CheckOutMinute);
        if (end > checkout + grace)
            extra += p.HalfFraction;

        return nights + extra;
    }
}

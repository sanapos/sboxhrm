using System.Text.Json;

namespace ZKTecoADMS.Api.Services;

/// <summary>Cờ bán hàng trong ExtraJson (không thêm cột DB).</summary>
public static class PosSellExtraJsonHelper
{
    public static bool AllowEditSaleTime(string? extraJson)
    {
        if (string.IsNullOrWhiteSpace(extraJson)) return false;
        try
        {
            using var doc = JsonDocument.Parse(extraJson);
            var root = doc.RootElement;
            if (Flag(root, "allowEditSaleTime", "AllowEditSaleTime"))
                return true;
            if ((root.TryGetProperty("sell", out var sell) ||
                 root.TryGetProperty("Sell", out sell))
                && sell.ValueKind == JsonValueKind.Object
                && Flag(sell, "allowEditSaleTime", "AllowEditSaleTime"))
                return true;
        }
        catch
        {
            // ExtraJson hỏng — giữ mặc định tắt.
        }
        return false;
    }

    /// Chỉ áp dụng khi hoàn thành đơn + cửa hàng bật cờ. Ngoài khoảng cho phép → giờ máy chủ.
    public static DateTime ResolveSaleAt(
        string? extraJson, DateTime? requested, DateTime utcNow, bool complete)
    {
        if (!complete || requested == null || !AllowEditSaleTime(extraJson))
            return utcNow;
        var utc = requested.Value.Kind switch
        {
            DateTimeKind.Utc => requested.Value,
            DateTimeKind.Local => requested.Value.ToUniversalTime(),
            _ => DateTime.SpecifyKind(requested.Value, DateTimeKind.Utc),
        };
        if (utc > utcNow.AddDays(1) || utc < utcNow.AddDays(-366))
            return utcNow;
        return utc;
    }

    static bool Flag(JsonElement obj, string camel, string pascal) =>
        (obj.TryGetProperty(camel, out var a) && a.ValueKind == JsonValueKind.True)
        || (obj.TryGetProperty(pascal, out var b) && b.ValueKind == JsonValueKind.True);
}

using System.Text.Json;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Lưu / đọc lại kết quả lần báo bếp gần nhất theo mã yêu cầu. Máy báo lại cùng mã
/// (mất mạng lúc server trả kết quả) được trả đúng các món lần đó để in phiếu.
/// </summary>
public static class PosKitchenSendReplay
{
    public static string Serialize(int sentLines, decimal sentQty, object sentItems, DateTime kitchenSentAt) =>
        JsonSerializer.Serialize(new { sentLines, sentQty, sentItems, kitchenSentAt });

    public record Snapshot(int SentLines, decimal SentQty, JsonElement? SentItems, DateTime KitchenSentAt);

    public static Snapshot? TryRead(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return null;
        try
        {
            var root = JsonSerializer.Deserialize<JsonElement>(json);
            if (root.ValueKind != JsonValueKind.Object) return null;
            var lines = root.TryGetProperty("sentLines", out var l) && l.TryGetInt32(out var li) ? li : 0;
            var qty = root.TryGetProperty("sentQty", out var q) && q.TryGetDecimal(out var qd) ? qd : 0m;
            JsonElement? items = root.TryGetProperty("sentItems", out var it) ? it.Clone() : null;
            var at = root.TryGetProperty("kitchenSentAt", out var t) && t.TryGetDateTime(out var td)
                ? td
                : DateTime.UtcNow;
            return new Snapshot(lines, qty, items, at);
        }
        catch (JsonException)
        {
            return null;
        }
    }
}

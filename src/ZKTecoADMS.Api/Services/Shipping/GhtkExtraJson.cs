using System.Text.Json;
using ZKTecoADMS.Api.Services;

namespace ZKTecoADMS.Api.Services.Shipping;

/// <summary>ExtraJson GHTK: pickAddressId + webhook hash (query ?hash=).</summary>
public static class GhtkExtraJson
{
    public const string WebhookSecretKey = "webhookSecret";
    public const string PickAddressIdKey = "pickAddressId";

    public static string? GetWebhookSecret(string? extraJson) =>
        ViettelPostExtraJson.GetWebhookSecret(extraJson);

    public static string? GetPickAddressId(string? extraJson)
    {
        if (string.IsNullOrWhiteSpace(extraJson)) return null;
        try
        {
            using var doc = JsonDocument.Parse(extraJson);
            var root = doc.RootElement;
            foreach (var key in new[] { PickAddressIdKey, "pick_address_id", "PickAddressId" })
            {
                if (root.TryGetProperty(key, out var p))
                {
                    var s = p.ValueKind == JsonValueKind.Number
                        ? p.GetRawText()
                        : p.GetString();
                    s = s?.Trim();
                    if (!string.IsNullOrWhiteSpace(s)) return s;
                }
            }
        }
        catch
        {
            // ignore
        }
        return null;
    }

    public static string Merge(
        string? extraJson, string? webhookSecret = null, string? pickAddressId = null)
    {
        var json = ViettelPostExtraJson.MergeWebhookSecret(extraJson, webhookSecret);
        if (pickAddressId == null) return json;

        Dictionary<string, JsonElement> map;
        try
        {
            using var doc = JsonDocument.Parse(string.IsNullOrWhiteSpace(json) ? "{}" : json);
            map = doc.RootElement.ValueKind == JsonValueKind.Object
                ? doc.RootElement.EnumerateObject()
                    .ToDictionary(p => p.Name, p => p.Value.Clone())
                : new Dictionary<string, JsonElement>(StringComparer.OrdinalIgnoreCase);
        }
        catch
        {
            map = new Dictionary<string, JsonElement>(StringComparer.OrdinalIgnoreCase);
        }

        var id = pickAddressId.Trim();
        if (id.Length == 0) map.Remove(PickAddressIdKey);
        else map[PickAddressIdKey] = JsonSerializer.SerializeToElement(id);

        return map.Count == 0 ? "" : JsonSerializer.Serialize(map);
    }

    public static bool MatchesHash(string? configuredSecret, string? queryHash)
    {
        if (string.IsNullOrWhiteSpace(configuredSecret)) return true;
        if (string.IsNullOrWhiteSpace(queryHash)) return false;
        return string.Equals(configuredSecret.Trim(), queryHash.Trim(), StringComparison.Ordinal);
    }
}

/// <summary>Map status_id webhook GHTK → nhãn + trạng thái đơn online.</summary>
public static class GhtkWebhookHelper
{
    public static string StatusLabel(int? statusId) => statusId switch
    {
        -1 => "Hủy đơn hàng",
        1 => "Chưa tiếp nhận",
        2 => "Đã tiếp nhận",
        3 => "Đã lấy hàng/Đã nhập kho",
        4 => "Đang giao hàng",
        5 => "Đã giao hàng",
        6 => "Đã đối soát",
        7 => "Không lấy được hàng",
        8 => "Hoãn lấy hàng",
        9 => "Không giao được hàng",
        10 => "Delay giao hàng",
        11 => "Đã đối soát công nợ trả hàng",
        12 => "Đang lấy hàng",
        13 => "Đơn bồi hoàn",
        20 => "Đang trả hàng",
        21 => "Đã trả hàng",
        45 => "Shipper báo đã giao",
        49 => "Shipper báo không giao được",
        123 => "Shipper báo đã lấy hàng",
        127 => "Shipper báo không lấy được",
        128 => "Shipper báo delay lấy hàng",
        410 => "Shipper báo delay giao hàng",
        _ => statusId == null ? "GHTK" : $"GHTK #{statusId}",
    };

    /// <summary>Map sang QrOnlineOrderStatuses khi đơn online; null = giữ nhãn GHTK.</summary>
    public static string? MapOnlineStatus(int? statusId) => statusId switch
    {
        -1 or 7 or 9 => QrOnlineOrderStatuses.Cancelled,
        5 or 6 or 45 => QrOnlineOrderStatuses.Delivered,
        3 or 4 or 10 or 12 or 123 => QrOnlineOrderStatuses.Shipping,
        1 or 2 or 8 or 128 => QrOnlineOrderStatuses.Confirmed,
        20 or 21 => QrOnlineOrderStatuses.Cancelled,
        _ => null,
    };
}

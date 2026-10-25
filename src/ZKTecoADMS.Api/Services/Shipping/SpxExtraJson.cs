using System.Text.Json;
using ZKTecoADMS.Api.Services;

namespace ZKTecoADMS.Api.Services.Shipping;

/// <summary>
/// ExtraJson SPX: webhook hash, prefix Open API, bảo hiểm / xem hàng / giao 1 phần.
/// </summary>
public static class SpxExtraJson
{
    public const string WebhookSecretKey = "webhookSecret";
    public const string OpenApiPrefixKey = "openApiPrefix";
    public const string AllowInspectKey = "allowInspect";
    public const string PartialDeliveryKey = "partialDelivery";
    public const string UseInsuranceKey = "useInsurance";
    public const string ServiceTypeKey = "serviceType";
    /// <summary>app-id / app-secret SPX cấp cho ứng dụng (ký header check-sign).</summary>
    public const string AppIdKey = "appId";
    public const string AppSecretKey = "appSecret";
    /// <summary>1 = SPX đến lấy (mặc định) · 2 = shop gửi tại bưu cục.</summary>
    public const string CollectTypeKey = "collectType";

    public static string? GetWebhookSecret(string? extraJson) =>
        ViettelPostExtraJson.GetWebhookSecret(extraJson);

    public static bool MatchesHash(string? configuredSecret, string? queryHash) =>
        GhtkExtraJson.MatchesHash(configuredSecret, queryHash);

    public static string? GetOpenApiPrefix(string? extraJson)
    {
        var raw = ReadString(extraJson, OpenApiPrefixKey, "open_api_prefix", "apiPrefix");
        if (string.IsNullOrWhiteSpace(raw)) return null;
        var p = raw.Trim();
        if (!p.StartsWith('/')) p = "/" + p;
        return p.TrimEnd('/');
    }

    public static bool GetBool(string? extraJson, string key, bool fallback = false)
    {
        if (string.IsNullOrWhiteSpace(extraJson)) return fallback;
        try
        {
            using var doc = JsonDocument.Parse(extraJson);
            if (!doc.RootElement.TryGetProperty(key, out var el)) return fallback;
            return el.ValueKind switch
            {
                JsonValueKind.True => true,
                JsonValueKind.False => false,
                JsonValueKind.String => el.GetString() is "1" or "true" or "yes",
                JsonValueKind.Number => el.TryGetInt32(out var n) && n != 0,
                _ => fallback,
            };
        }
        catch
        {
            return fallback;
        }
    }

    public static string? ReadString(string? extraJson, params string[] keys)
    {
        if (string.IsNullOrWhiteSpace(extraJson) || keys.Length == 0) return null;
        try
        {
            using var doc = JsonDocument.Parse(extraJson);
            foreach (var key in keys)
            {
                if (!doc.RootElement.TryGetProperty(key, out var el)) continue;
                var s = el.ValueKind == JsonValueKind.String ? el.GetString() : el.ToString();
                if (!string.IsNullOrWhiteSpace(s)) return s.Trim();
            }
        }
        catch
        {
            // ignore
        }
        return null;
    }
}

/// <summary>Map trạng thái SPX (Open API + tracking công khai + webhook) → nhãn / đơn online.</summary>
public static class SpxWebhookHelper
{
    public static string StatusLabel(string? status)
    {
        var n = Normalize(status);
        return n switch
        {
            // Mã status_code chính thức (docs «Order status code»).
            "1001" or "pending_pickup" => "Chờ lấy hàng",
            "2001" => "Đang trung chuyển",
            "2006" => "Đang giao hàng",
            "3001" => "Tạm hoãn",
            "4001" => "Đã giao hàng",
            "5001" or "pickup_failed" => "Lấy hàng thất bại",
            "5002" or "damaged" => "Hàng hư hỏng",
            "5003" or "lost" => "Thất lạc",
            "6001" => "Đang hoàn hàng",
            "6002" or "return_failed" => "Hoàn hàng thất bại",
            "6003" => "Đã hoàn hàng",
            "7001" => "Đã hủy",
            "created" or "pending" or "new" or "order_created" => "Đã tạo đơn",
            "pickup" or "picked_up" or "picked" or "collected" => "Đã lấy hàng",
            "in_transit" or "transit" or "hub_in" or "hub_out" => "Đang trung chuyển",
            "delivering" or "out_for_delivery" or "on_delivery" => "Đang giao hàng",
            "delivered" or "completed" or "success" => "Đã giao hàng",
            "cancelled" or "canceled" or "void" => "Đã hủy",
            "returned" or "returning" or "rto" => "Hoàn hàng",
            "failed" or "undelivered" or "delivery_failed" => "Giao thất bại",
            "on_hold" or "delay" => "Tạm hoãn",
            _ => string.IsNullOrWhiteSpace(status) ? "SPX" : status.Trim(),
        };
    }

    public static string? MapOnlineStatus(string? status)
    {
        var n = Normalize(status);
        return n switch
        {
            "4001" => QrOnlineOrderStatuses.Delivered,
            "6003" or "7001" => QrOnlineOrderStatuses.Cancelled,
            "2001" or "2006" or "3001" or "5001" or "5002" or "5003" or "6001" or "6002"
                or "pickup_failed" or "return_failed" or "lost" or "damaged" => QrOnlineOrderStatuses.Shipping,
            "1001" or "pending_pickup" => QrOnlineOrderStatuses.Confirmed,
            "delivered" or "completed" or "success" => QrOnlineOrderStatuses.Delivered,
            "cancelled" or "canceled" or "void" or "failed" or "undelivered"
                or "delivery_failed" or "returned" or "returning" or "rto"
                => QrOnlineOrderStatuses.Cancelled,
            "pickup" or "picked_up" or "picked" or "collected" or "in_transit"
                or "transit" or "hub_in" or "hub_out" or "delivering"
                or "out_for_delivery" or "on_delivery"
                => QrOnlineOrderStatuses.Shipping,
            "created" or "pending" or "new" or "order_created" or "on_hold" or "delay"
                => QrOnlineOrderStatuses.Confirmed,
            _ => null,
        };
    }

    public static string Normalize(string? status)
    {
        if (string.IsNullOrWhiteSpace(status)) return "";
        return status.Trim().ToLowerInvariant()
            .Replace(' ', '_')
            .Replace('-', '_');
    }
}

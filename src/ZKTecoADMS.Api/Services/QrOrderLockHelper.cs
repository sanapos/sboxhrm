using System.Text.Json;
using System.Text.Json.Nodes;

namespace ZKTecoADMS.Api.Services;

/// <summary>Khóa QR order ngoài quán + xác nhận đơn trước khi in bếp + QR đặt online.</summary>
public static class QrOrderLockHelper
{
    public readonly record struct Options(
        bool RequireOpenSession,
        bool RequireGeofence,
        bool RequireOrderConfirmation,
        bool EnableOnline,
        string? OnlineToken,
        bool OnlineAutoConfirm,
        bool OnlineAutoPrintKitchen,
        bool OnlineAutoPay,
        bool OnlineAutoPrintProvisional,
        bool OnlineAutoCreateShipment,
        string? OnlineDefaultCarrierCode,
        string? StoreZalo,
        bool UseCustomMenu);

    public static Options Parse(string? extraJson)
    {
        if (string.IsNullOrWhiteSpace(extraJson))
            return default;
        try
        {
            using var doc = JsonDocument.Parse(extraJson);
            if (!TryGetQr(doc.RootElement, out var qr))
                return default;
            return new Options(
                Flag(qr, "requireOpenSession", "RequireOpenSession"),
                Flag(qr, "requireGeofence", "RequireGeofence"),
                Flag(qr, "requireOrderConfirmation", "RequireOrderConfirmation"),
                Flag(qr, "enableOnline", "EnableOnline"),
                Str(qr, "onlineToken", "OnlineToken"),
                Flag(qr, "onlineAutoConfirm", "OnlineAutoConfirm"),
                Flag(qr, "onlineAutoPrintKitchen", "OnlineAutoPrintKitchen"),
                Flag(qr, "onlineAutoPay", "OnlineAutoPay"),
                Flag(qr, "onlineAutoPrintProvisional", "OnlineAutoPrintProvisional"),
                Flag(qr, "onlineAutoCreateShipment", "OnlineAutoCreateShipment"),
                Str(qr, "onlineDefaultCarrierCode", "OnlineDefaultCarrierCode"),
                Str(qr, "storeZalo", "StoreZalo"),
                Flag(qr, "useCustomMenu", "UseCustomMenu"));
        }
        catch
        {
            return default;
        }
    }

    public static string Merge(
        string? existing,
        bool requireOpenSession,
        bool requireGeofence,
        bool requireOrderConfirmation = false)
    {
        var root = ParseRoot(existing);
        var qr = QrObject(root);
        qr["requireOpenSession"] = requireOpenSession;
        qr["requireGeofence"] = requireGeofence;
        qr["requireOrderConfirmation"] = requireOrderConfirmation;
        root["qrOrder"] = qr;
        return root.ToJsonString();
    }

    public static string MergeOnline(string? existing, bool enableOnline, string? onlineToken)
    {
        var root = ParseRoot(existing);
        var qr = QrObject(root);
        qr["enableOnline"] = enableOnline;
        if (!string.IsNullOrWhiteSpace(onlineToken))
            qr["onlineToken"] = onlineToken.Trim();
        root["qrOrder"] = qr;
        return root.ToJsonString();
    }

    public readonly record struct Brand(string? LogoUrl, string[] Banners);

    public static Brand ParseBrand(string? extraJson)
    {
        if (string.IsNullOrWhiteSpace(extraJson))
            return new Brand(null, []);
        try
        {
            using var doc = JsonDocument.Parse(extraJson);
            if (!TryGetQr(doc.RootElement, out var qr))
                return new Brand(null, []);
            var logo = Str(qr, "logoUrl", "LogoUrl");
            var banners = new List<string>();
            if ((qr.TryGetProperty("banners", out var arr) || qr.TryGetProperty("Banners", out arr))
                && arr.ValueKind == JsonValueKind.Array)
            {
                foreach (var x in arr.EnumerateArray())
                {
                    if (x.ValueKind != JsonValueKind.String) continue;
                    var s = (x.GetString() ?? "").Trim();
                    if (s.Length == 0) continue;
                    banners.Add(s);
                    if (banners.Count >= 5) break;
                }
            }
            return new Brand(logo, banners.ToArray());
        }
        catch
        {
            return new Brand(null, []);
        }
    }

    public static string MergeCustomMenu(string? existing, bool useCustomMenu)
    {
        var root = ParseRoot(existing);
        var qr = QrObject(root);
        qr["useCustomMenu"] = useCustomMenu;
        root["qrOrder"] = qr;
        return root.ToJsonString();
    }

    public static string MergeBrand(string? existing, string? logoUrl, IEnumerable<string>? banners)
    {
        var root = ParseRoot(existing);
        var qr = QrObject(root);
        var logo = (logoUrl ?? "").Trim();
        if (logo.Length == 0) qr.Remove("logoUrl");
        else qr["logoUrl"] = logo;
        var arr = new JsonArray();
        foreach (var b in (banners ?? [])
                     .Select(x => (x ?? "").Trim())
                     .Where(x => x.Length > 0)
                     .Take(5))
            arr.Add(b);
        qr["banners"] = arr;
        root["qrOrder"] = qr;
        return root.ToJsonString();
    }

    public static bool IsInsideAny(double lat, double lng,
        IEnumerable<(double Latitude, double Longitude, double RadiusMeters)> fences)
    {
        if (lat is < -90 or > 90 || lng is < -180 or > 180)
            return false;
        foreach (var f in fences)
        {
            var r = f.RadiusMeters > 0 ? f.RadiusMeters : 80;
            if (DistanceMeters(lat, lng, f.Latitude, f.Longitude) <= r)
                return true;
        }
        return false;
    }

    public static double DistanceMeters(double lat1, double lon1, double lat2, double lon2)
    {
        const double earth = 6371000;
        var r1 = lat1 * Math.PI / 180;
        var r2 = lat2 * Math.PI / 180;
        var dLat = (lat2 - lat1) * Math.PI / 180;
        var dLon = (lon2 - lon1) * Math.PI / 180;
        var a = Math.Sin(dLat / 2) * Math.Sin(dLat / 2)
            + Math.Cos(r1) * Math.Cos(r2) * Math.Sin(dLon / 2) * Math.Sin(dLon / 2);
        return earth * 2 * Math.Atan2(Math.Sqrt(a), Math.Sqrt(1 - a));
    }

    static JsonObject ParseRoot(string? existing)
    {
        if (!string.IsNullOrWhiteSpace(existing))
        {
            try
            {
                return JsonNode.Parse(existing) as JsonObject ?? [];
            }
            catch
            {
                return [];
            }
        }
        return [];
    }

    static JsonObject QrObject(JsonObject root)
    {
        if (root["qrOrder"] is JsonObject qr) return qr;
        if (root["QrOrder"] is JsonObject qr2) return qr2;
        return [];
    }

    static bool TryGetQr(JsonElement root, out JsonElement qr)
    {
        if (root.ValueKind == JsonValueKind.Object
            && (root.TryGetProperty("qrOrder", out qr) || root.TryGetProperty("QrOrder", out qr))
            && qr.ValueKind == JsonValueKind.Object)
            return true;
        qr = default;
        return false;
    }

    static bool Flag(JsonElement obj, string camel, string pascal) =>
        (obj.TryGetProperty(camel, out var a) && a.ValueKind == JsonValueKind.True)
        || (obj.TryGetProperty(pascal, out var b) && b.ValueKind == JsonValueKind.True);

    static string? Str(JsonElement obj, string camel, string pascal)
    {
        if (obj.TryGetProperty(camel, out var a) && a.ValueKind == JsonValueKind.String)
            return a.GetString();
        if (obj.TryGetProperty(pascal, out var b) && b.ValueKind == JsonValueKind.String)
            return b.GetString();
        return null;
    }
}

using System.Text.Json;
using System.Text.Json.Nodes;

namespace ZKTecoADMS.Api.Services;

/// <summary>Khóa QR order ngoài quán + xác nhận đơn trước khi in bếp.</summary>
public static class QrOrderLockHelper
{
    public readonly record struct Options(
        bool RequireOpenSession,
        bool RequireGeofence,
        bool RequireOrderConfirmation);

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
                Flag(qr, "requireOrderConfirmation", "RequireOrderConfirmation"));
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
        JsonObject root;
        if (!string.IsNullOrWhiteSpace(existing))
        {
            try
            {
                root = JsonNode.Parse(existing) as JsonObject ?? [];
            }
            catch
            {
                root = [];
            }
        }
        else
        {
            root = [];
        }

        root["qrOrder"] = new JsonObject
        {
            ["requireOpenSession"] = requireOpenSession,
            ["requireGeofence"] = requireGeofence,
            ["requireOrderConfirmation"] = requireOrderConfirmation,
        };
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
}

using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Nodes;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Bộ điều khiển đèn bàn bi-a (ESP32-C3 + relay) — cấu hình nằm trong
/// PosStoreSellSettings.ExtraJson → "bidaLight": { "secret": "...", "pausedOn": true }.
/// Thiết bị giữ khóa dạng "{storeId:N}-{secret}" và hỏi trạng thái bàn định kỳ.
/// </summary>
public static class PosBidaLightHelper
{
    const string Node = "bidaLight";

    public sealed record Config(string? Secret, bool PausedOn);

    public static Config Read(string? extraJson)
    {
        var o = ParseObject(extraJson)?[Node] as JsonObject;
        if (o == null) return new Config(null, true);
        var secret = o["secret"]?.GetValue<string>();
        var pausedOn = o["pausedOn"] is JsonValue v && v.TryGetValue<bool>(out var b) ? b : true;
        return new Config(string.IsNullOrWhiteSpace(secret) ? null : secret, pausedOn);
    }

    public static string Write(string? extraJson, Config cfg)
    {
        var root = ParseObject(extraJson) ?? new JsonObject();
        if (cfg.Secret == null)
            root.Remove(Node);
        else
            root[Node] = new JsonObject { ["secret"] = cfg.Secret, ["pausedOn"] = cfg.PausedOn };
        return root.ToJsonString();
    }

    /// <summary>
    /// App lưu ExtraJson nguyên khối — bản đang mở trên máy khác có thể cũ hơn khóa vừa đổi.
    /// Nút "bidaLight" chỉ đổi qua API riêng nên luôn giữ bản trên server.
    /// </summary>
    public static string? KeepServerNode(string? incoming, string? current)
    {
        if (incoming == null) return null;
        var cur = ParseObject(current)?[Node];
        var root = ParseObject(incoming);
        if (root == null) return incoming;
        if (cur == null && root[Node] == null) return incoming;
        root.Remove(Node);
        if (cur != null) root[Node] = cur.DeepClone();
        return root.ToJsonString();
    }

    public static string NewSecret() => Convert.ToHexString(RandomNumberGenerator.GetBytes(12)).ToLowerInvariant();

    public static string DeviceKey(Guid storeId, string secret) => $"{storeId:N}-{secret}";

    public static bool TryParseDeviceKey(string? key, out Guid storeId, out string secret)
    {
        storeId = Guid.Empty;
        secret = "";
        var k = (key ?? "").Trim();
        var dash = k.IndexOf('-');
        if (dash != 32 || !Guid.TryParseExact(k[..dash], "N", out storeId)) return false;
        secret = k[(dash + 1)..];
        return secret.Length > 0;
    }

    public static bool SecretMatches(string? expected, string given) =>
        expected != null
        && CryptographicOperations.FixedTimeEquals(Encoding.UTF8.GetBytes(expected), Encoding.UTF8.GetBytes(given));

    static JsonObject? ParseObject(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return null;
        try { return JsonNode.Parse(json) as JsonObject; }
        catch { return null; }
    }
}

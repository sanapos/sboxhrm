using System.Text.Json;

namespace ZKTecoADMS.Api.Services.Shipping;

/// <summary>ExtraJson cấu hình Viettel Post (webhook secret, …).</summary>
public static class ViettelPostExtraJson
{
    public const string WebhookSecretKey = "webhookSecret";

    public static string? GetWebhookSecret(string? extraJson)
    {
        if (string.IsNullOrWhiteSpace(extraJson)) return null;
        try
        {
            using var doc = JsonDocument.Parse(extraJson);
            var root = doc.RootElement;
            foreach (var key in new[] { WebhookSecretKey, "webhook_secret", "WebhookSecret" })
            {
                if (root.TryGetProperty(key, out var p) && p.ValueKind == JsonValueKind.String)
                {
                    var s = p.GetString()?.Trim();
                    if (!string.IsNullOrWhiteSpace(s)) return s;
                }
            }
        }
        catch
        {
            // Legacy: whole string is the secret.
            var t = extraJson.Trim();
            if (t.Length > 0 && !t.StartsWith('{')) return t;
        }
        return null;
    }

    public static string MergeWebhookSecret(string? extraJson, string? secret)
    {
        var trimmed = (secret ?? "").Trim();
        Dictionary<string, JsonElement>? map = null;
        if (!string.IsNullOrWhiteSpace(extraJson))
        {
            try
            {
                using var doc = JsonDocument.Parse(extraJson);
                if (doc.RootElement.ValueKind == JsonValueKind.Object)
                {
                    map = doc.RootElement.EnumerateObject()
                        .ToDictionary(p => p.Name, p => p.Value.Clone());
                }
            }
            catch
            {
                // ignore
            }
        }

        map ??= new Dictionary<string, JsonElement>(StringComparer.OrdinalIgnoreCase);
        if (trimmed.Length == 0)
            map.Remove(WebhookSecretKey);
        else
            map[WebhookSecretKey] = JsonSerializer.SerializeToElement(trimmed);

        if (map.Count == 0) return "";
        return JsonSerializer.Serialize(map);
    }

    public static bool MatchesWebhookAuth(string? configuredSecret, string? authorization, string? bodyToken)
    {
        if (string.IsNullOrWhiteSpace(configuredSecret)) return true;

        var secret = configuredSecret.Trim();
        if (!string.IsNullOrWhiteSpace(bodyToken)
            && string.Equals(bodyToken.Trim(), secret, StringComparison.Ordinal))
            return true;

        if (string.IsNullOrWhiteSpace(authorization)) return false;
        var auth = authorization.Trim();
        if (auth.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase))
            auth = auth[7..].Trim();
        return string.Equals(auth, secret, StringComparison.Ordinal)
               || auth.Contains(secret, StringComparison.Ordinal);
    }
}

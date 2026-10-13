using System.Text.Json;
using System.Text.Json.Nodes;

namespace ZKTecoADMS.Application.Behaviours;

/// <summary>
/// Che dữ liệu nhạy cảm trước khi ghi log request (mật khẩu, token, mã PIN, OTP, khóa API…).
/// Trước đây LoggingBehaviour ghi nguyên LoginCommand → log server có mật khẩu dạng chữ thường.
/// </summary>
public static class LogRedactor
{
    public const string Mask = "***";
    public const int MaxLength = 4000;

    static readonly string[] SensitiveParts =
    {
        "password", "passwd", "pwd", "token", "secret", "apikey", "api_key",
        "otp", "pincode", "privatekey", "credential", "signature", "cvv", "cardnumber",
    };

    static readonly HashSet<string> SensitiveExact = new(StringComparer.OrdinalIgnoreCase)
    {
        "pin", "key", "code_verifier", "authorization",
    };

    public static bool IsSensitiveKey(string key)
    {
        if (string.IsNullOrEmpty(key)) return false;
        if (SensitiveExact.Contains(key)) return true;
        var k = key.Replace("-", "").Replace("_", "").ToLowerInvariant();
        // deviceKey (khóa thiết bị dùng khi refresh), accessKey, hmacKey… — mọi «…Key».
        if (k.EndsWith("key")) return true;
        foreach (var p in SensitiveParts)
            if (k.Contains(p.Replace("_", ""))) return true;
        return false;
    }

    static readonly JsonSerializerOptions Options = new()
    {
        WriteIndented = false,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
    };

    /// <summary>JSON của [request] đã che trường nhạy cảm (mọi cấp), cắt bớt nếu quá dài.</summary>
    public static string Serialize(object? request)
    {
        string json;
        try
        {
            var node = JsonSerializer.SerializeToNode(request, request?.GetType() ?? typeof(object), Options);
            Redact(node);
            json = node?.ToJsonString(Options) ?? "null";
        }
        catch (Exception ex)
        {
            // Không serialize được (vòng tham chiếu, Stream…) → không ghi dữ liệu, chỉ ghi lý do.
            return $"<không ghi dữ liệu: {ex.GetType().Name}>";
        }
        return json.Length <= MaxLength ? json : json[..MaxLength] + $"…(+{json.Length - MaxLength} ký tự)";
    }

    static void Redact(JsonNode? node)
    {
        switch (node)
        {
            case JsonObject obj:
                foreach (var key in obj.Select(p => p.Key).ToList())
                {
                    if (IsSensitiveKey(key))
                    {
                        if (obj[key] is not null) obj[key] = Mask;
                    }
                    else
                    {
                        Redact(obj[key]);
                    }
                }
                break;
            case JsonArray arr:
                foreach (var item in arr) Redact(item);
                break;
        }
    }
}

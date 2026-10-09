using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Giới hạn làm mới token theo từng phiên (refresh token), không theo IP: một thiết bị lặp làm mới
/// chỉ tự chặn chính nó — không làm các máy khác cùng văn phòng (chung IP) bị 429 / bị đăng xuất.
/// </summary>
public static class RefreshTokenRateKey
{
    public const string Policy = "auth-refresh";
    public const string ItemKey = "sbox.refresh-rate-key";
    const int MaxBody = 16 * 1024;

    public static async Task CaptureAsync(HttpContext context, Func<Task> next)
    {
        if (HttpMethods.IsPost(context.Request.Method)
            && context.Request.Path.Equals("/api/auth/refresh", StringComparison.OrdinalIgnoreCase)
            && (context.Request.ContentLength ?? 0) is > 0 and <= MaxBody)
        {
            try
            {
                context.Request.EnableBuffering();
                using var doc = await JsonDocument.ParseAsync(context.Request.Body, cancellationToken: context.RequestAborted);
                var token = Find(doc.RootElement, "refreshToken");
                if (!string.IsNullOrEmpty(token)) context.Items[ItemKey] = Key(token);
            }
            catch (JsonException)
            {
                // Body lạ: để action tự báo lỗi; bộ giới hạn rơi về theo IP.
            }
            finally
            {
                context.Request.Body.Position = 0;
            }
        }
        await next();
    }

    /// <summary>«rt:» + 16 ký tự băm SHA-256 — không giữ mã gốc trong bộ nhớ bộ giới hạn.</summary>
    public static string Key(string refreshToken) =>
        "rt:" + Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(refreshToken)))[..16];

    static string? Find(JsonElement root, string name)
    {
        if (root.ValueKind != JsonValueKind.Object) return null;
        foreach (var p in root.EnumerateObject())
            if (string.Equals(p.Name, name, StringComparison.OrdinalIgnoreCase) && p.Value.ValueKind == JsonValueKind.String)
                return p.Value.GetString();
        return null;
    }
}

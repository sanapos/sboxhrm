using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace ZKTecoADMS.Api.Services.PaymentGateway;

public sealed record TingeeOpenApiResult(
    string Code,
    string Message,
    JsonElement Data,
    string Raw);

public interface ITingeeOpenApiClient
{
    Task<TingeeOpenApiResult> PostAsync(JsonObject body, string path, CancellationToken ct = default);
}

public sealed class TingeeOpenApiClient(
    IHttpClientFactory httpFactory,
    IPosPlatformTingeeSettingService platform) : ITingeeOpenApiClient
{
    static readonly JsonSerializerOptions JsonOpts = new()
    {
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
        WriteIndented = false,
    };

    public async Task<TingeeOpenApiResult> PostAsync(
        JsonObject body, string path, CancellationToken ct = default)
    {
        var auth = await platform.RequireOpenApiAuthAsync(ct);
        var json = body.ToJsonString(JsonOpts);
        var ts = DateTime.UtcNow.AddHours(7).ToString("yyyyMMddHHmmssfff", CultureInfo.InvariantCulture);
        var sig = HmacSha512Hex($"{ts}:{json}", auth.Secret);
        var url = $"{auth.BaseUrl.TrimEnd('/')}/{path.TrimStart('/')}";

        using var req = new HttpRequestMessage(HttpMethod.Post, url);
        req.Content = new StringContent(json, Encoding.UTF8, "application/json");
        req.Headers.TryAddWithoutValidation("x-client-id", auth.ClientId);
        req.Headers.TryAddWithoutValidation("x-request-timestamp", ts);
        req.Headers.TryAddWithoutValidation("x-signature", sig);

        var http = httpFactory.CreateClient("tingee-open-api");
        using var res = await http.SendAsync(req, ct);
        var raw = await res.Content.ReadAsStringAsync(ct);
        return Parse(raw, res.StatusCode);
    }

    static TingeeOpenApiResult Parse(string raw, System.Net.HttpStatusCode status)
    {
        if (string.IsNullOrWhiteSpace(raw))
            return new(((int)status).ToString(), "Tingee không trả dữ liệu", default, raw);

        try
        {
            using var doc = JsonDocument.Parse(raw);
            var root = doc.RootElement.Clone();
            var code = root.TryGetProperty("code", out var c) ? (c.GetString() ?? c.GetRawText()) : ((int)status).ToString();
            var msg = root.TryGetProperty("message", out var m) ? (m.GetString() ?? "") : raw;
            var data = root.TryGetProperty("data", out var d) ? d.Clone() : default;
            return new(code, msg, data, raw);
        }
        catch (JsonException)
        {
            var snippet = raw.Length > 180 ? raw[..180] : raw;
            return new(((int)status).ToString(), snippet, default, raw);
        }
    }

    static string HmacSha512Hex(string message, string secret)
    {
        var hash = HMACSHA512.HashData(Encoding.UTF8.GetBytes(secret), Encoding.UTF8.GetBytes(message));
        return Convert.ToHexString(hash).ToLowerInvariant();
    }
}

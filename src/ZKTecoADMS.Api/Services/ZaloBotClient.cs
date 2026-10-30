using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace ZKTecoADMS.Api.Services;

/// <summary>Kết quả gọi Zalo Bot API: { ok, result, error_code, description }.</summary>
public sealed record ZaloBotResult(bool Ok, int? ErrorCode, string? Description, JsonElement? Result)
{
    /// <summary>Token sai / hết hạn — thử lại vô ích.</summary>
    public bool TokenInvalid => ErrorCode == 401;

    /// <summary>Vượt hạn mức gọi API — chờ rồi thử lại.</summary>
    public bool RateLimited => ErrorCode == 429;

    public string Error => string.IsNullOrWhiteSpace(Description) ? $"Lỗi Zalo {ErrorCode}" : $"{Description} ({ErrorCode})";
}

public interface IZaloBotClient
{
    Task<ZaloBotResult> GetMeAsync(string token, CancellationToken ct = default);
    Task<ZaloBotResult> SetWebhookAsync(string token, string url, string secret, CancellationToken ct = default);
    Task<ZaloBotResult> SendMessageAsync(string token, string chatId, string text, CancellationToken ct = default);
}

/// <summary>
/// Zalo Bot Platform (bot.zapps.me/docs): POST https://bot-api.zaloplatforms.com/bot{TOKEN}/{method}, thân JSON.
/// Tin văn bản tối đa 2000 ký tự.
/// </summary>
public sealed class ZaloBotClient(IHttpClientFactory httpFactory, ILogger<ZaloBotClient> logger) : IZaloBotClient
{
    public const string HttpClientName = "zalo-bot";
    public const string BaseUrl = "https://bot-api.zaloplatforms.com";
    public const int MaxTextLength = 2000;

    public Task<ZaloBotResult> GetMeAsync(string token, CancellationToken ct = default) =>
        CallAsync(token, "getMe", new { }, ct);

    public Task<ZaloBotResult> SetWebhookAsync(string token, string url, string secret, CancellationToken ct = default) =>
        CallAsync(token, "setWebhook", new { url, secret_token = secret }, ct);

    public Task<ZaloBotResult> SendMessageAsync(string token, string chatId, string text, CancellationToken ct = default) =>
        CallAsync(token, "sendMessage", new { chat_id = chatId, text = ZaloBotText.Truncate(text, MaxTextLength) }, ct);

    async Task<ZaloBotResult> CallAsync(string token, string method, object body, CancellationToken ct)
    {
        try
        {
            var http = httpFactory.CreateClient(HttpClientName);
            using var res = await http.PostAsJsonAsync($"{BaseUrl}/bot{token}/{method}", body, ct);
            var raw = await res.Content.ReadAsStringAsync(ct);
            return Parse(raw, (int)res.StatusCode);
        }
        catch (OperationCanceledException) when (!ct.IsCancellationRequested)
        {
            return new ZaloBotResult(false, 408, "Zalo không phản hồi", null);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Zalo bot {Method} failed", method);
            return new ZaloBotResult(false, null, "Không kết nối được Zalo", null);
        }
    }

    sealed class Envelope
    {
        [JsonPropertyName("ok")] public bool Ok { get; set; }
        [JsonPropertyName("error_code")] public int? ErrorCode { get; set; }
        [JsonPropertyName("description")] public string? Description { get; set; }
        [JsonPropertyName("result")] public JsonElement? Result { get; set; }
    }

    /// <summary>Thân trả về lỗi không phải JSON (cổng trung gian) → dùng mã HTTP.</summary>
    public static ZaloBotResult Parse(string raw, int httpStatus)
    {
        try
        {
            var e = JsonSerializer.Deserialize<Envelope>(raw);
            if (e != null)
                return new ZaloBotResult(e.Ok, e.Ok ? null : e.ErrorCode ?? httpStatus, e.Description, e.Result);
        }
        catch (JsonException) { }
        return new ZaloBotResult(false, httpStatus, httpStatus >= 400 ? $"HTTP {httpStatus}" : "Phản hồi Zalo không hợp lệ", null);
    }
}

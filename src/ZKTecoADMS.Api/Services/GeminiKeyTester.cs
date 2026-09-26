namespace ZKTecoADMS.Api.Services;

/// <summary>Kiểm tra lần lượt từng khóa Gemini (nút «Kiểm tra»): hoạt động / hết lượt / sai khóa.</summary>
public static class GeminiKeyTester
{
    public sealed record KeyResult(int Index, string Key, string Status, string Message);

    public static async Task<List<KeyResult>> TestAllAsync(
        GeminiConfig cfg, IConfiguration configuration, ILogger<GeminiAiService> logger, CancellationToken ct)
    {
        var results = new List<KeyResult>();
        var keys = cfg.ApiKeys.Count > 0 ? cfg.ApiKeys : [cfg.ApiKey];
        for (var i = 0; i < keys.Count; i++)
        {
            var gemini = new GeminiAiService(configuration, logger);
            gemini.UpdateConfig(keys[i], cfg.Model, 1024, cfg.Temperature, true);
            try
            {
                await gemini.GenerateJsonAsync(
                    "Bạn là bộ kiểm tra kết nối. Chỉ trả JSON.",
                    "Trả về {\"ok\": true}",
                    maxTokens: 256,
                    cancellationToken: ct);
                results.Add(new(i + 1, GeminiKeyPool.Mask(keys[i]), "ok", "Hoạt động"));
            }
            catch (AiApiException ex) when (ex.IsQuotaError)
            {
                GeminiKeyPool.MarkExhausted(keys[i], TimeSpan.FromMinutes(15));
                results.Add(new(i + 1, GeminiKeyPool.Mask(keys[i]), "quota", "Khóa đúng nhưng tạm hết lượt"));
            }
            catch (AiApiException ex) when (ex.IsAuthError)
            {
                GeminiKeyPool.MarkExhausted(keys[i], TimeSpan.FromHours(6));
                results.Add(new(i + 1, GeminiKeyPool.Mask(keys[i]), "invalid", "Khóa sai / hết hạn / không có quyền"));
            }
            catch (Exception ex) when (ex is AiApiException or InvalidOperationException or HttpRequestException or TaskCanceledException)
            {
                results.Add(new(i + 1, GeminiKeyPool.Mask(keys[i]), "error", ex.Message));
            }
        }
        return results;
    }

    /// <summary>«Khóa 1 AIza****abcd: Hoạt động · Khóa 2 …: Tạm hết lượt».</summary>
    public static string Detail(IReadOnlyList<KeyResult> r) =>
        string.Join(" · ", r.Select(x => $"Khóa {x.Index} {x.Key}: {x.Message}"));

    public static string Summary(IReadOnlyList<KeyResult> r)
    {
        var ok = r.Count(x => x.Status == "ok");
        return ok > 0
            ? $"{ok}/{r.Count} khóa hoạt động — khóa hết lượt sẽ tự chuyển sang khóa kế tiếp."
            : $"Không khóa nào dùng được ({r.Count} khóa).";
    }
}

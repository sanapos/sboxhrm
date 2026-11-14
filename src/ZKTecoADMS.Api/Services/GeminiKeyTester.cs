namespace ZKTecoADMS.Api.Services;

/// <summary>Kiểm tra từng khóa Gemini (nút «Kiểm tra»): hoạt động / hết lượt / sai khóa.</summary>
public static class GeminiKeyTester
{
    public sealed record KeyResult(int Index, string Key, string Status, string Message);

    /// <summary>
    /// Ngân sách cho cả nút «Kiểm tra»: nginx cắt /api/ ở 60 giây, mà mỗi lần Google quá tải phải chờ 20–45 giây mới
    /// nhận 503. Hết ngân sách thì báo «chưa kiểm tra xong» còn hơn để người dùng nhận trang 504.
    /// </summary>
    public static readonly TimeSpan Budget = TimeSpan.FromSeconds(40);

    /// <summary>
    /// Chờ tối đa bấy nhiêu cho MỘT model. Google quá tải thì không trả lời (có lần treo quá 2 phút mới báo 503) —
    /// bỏ sớm để còn kịp thử model dự phòng, vốn vẫn trả lời trong 1–2 giây.
    /// </summary>
    public static readonly TimeSpan AttemptTimeout = TimeSpan.FromSeconds(12);

    /// <summary>Model sẽ thử: model đã chọn rồi tới model dự phòng, model đang quá tải xếp cuối.</summary>
    internal static List<string> Models(GeminiConfig cfg) =>
        GeminiKeyPool.OrderModels([cfg.Model, .. TenantScopedGeminiAiService.FallbackModels]);

    public static async Task<List<KeyResult>> TestAllAsync(
        GeminiConfig cfg, IConfiguration configuration, ILogger<GeminiAiService> logger, CancellationToken ct)
    {
        var keys = cfg.ApiKeys.Count > 0 ? cfg.ApiKeys : [cfg.ApiKey];
        // Thử song song: chạy nối tiếp thì 3 khóa × mỗi model quá tải 20–45 giây là vượt xa giới hạn 60 giây của nginx.
        using var budget = CancellationTokenSource.CreateLinkedTokenSource(ct);
        budget.CancelAfter(Budget);
        var results = await Task.WhenAll(
            keys.Select((key, i) => TestOneAsync(i + 1, key, cfg, configuration, logger, budget.Token)));
        return [.. results];
    }

    static async Task<KeyResult> TestOneAsync(
        int index, string key, GeminiConfig cfg, IConfiguration configuration,
        ILogger<GeminiAiService> logger, CancellationToken ct)
    {
        var masked = GeminiKeyPool.Mask(key);
        try
        {
            string? usedModel = null;
            AiApiException? modelErr = null;
            var timedOut = false;
            // Model đã chọn trước; Google báo model không còn cho khóa này (404) / quá tải (503) / không trả lời
            // → bỏ qua, thử model dự phòng.
            foreach (var model in Models(cfg))
            {
                var gemini = new GeminiAiService(configuration, logger);
                gemini.UpdateConfig(key, model, 1024, cfg.Temperature, true);
                using var attempt = CancellationTokenSource.CreateLinkedTokenSource(ct);
                attempt.CancelAfter(AttemptTimeout);
                try
                {
                    await gemini.GenerateJsonAsync(
                        "Bạn là bộ kiểm tra kết nối. Chỉ trả JSON.",
                        "Trả về {\"ok\": true}",
                        maxTokens: 256,
                        cancellationToken: attempt.Token);
                    usedModel = model;
                    break;
                }
                catch (AiApiException ex) when (ex.StatusCode is 404 or 503)
                {
                    // 503 = model quá tải với mọi khóa, không riêng khóa này — nhớ lại để khóa khác và các lời gọi
                    // sau đó bỏ qua ngay thay vì chờ thêm 20–45 giây nữa.
                    if (ex.StatusCode == 503)
                        GeminiKeyPool.MarkModelOverloaded(model, TenantScopedGeminiAiService.OverloadWindow);
                    modelErr = ex;
                }
                catch (OperationCanceledException) when (attempt.IsCancellationRequested && !ct.IsCancellationRequested)
                {
                    GeminiKeyPool.MarkModelOverloaded(model, TenantScopedGeminiAiService.OverloadWindow);
                    timedOut = true;
                }
            }
            if (usedModel == null)
            {
                if (modelErr != null) throw modelErr;
                return new(index, masked, "timeout", timedOut
                    ? $"Model nào cũng không trả lời trong {AttemptTimeout.TotalSeconds:0} giây — Google đang quá tải, thử lại sau"
                    : "Không có model nào để thử");
            }
            return new(index, masked, "ok",
                string.Equals(usedModel, cfg.Model, StringComparison.OrdinalIgnoreCase)
                    ? "Hoạt động"
                    : $"Hoạt động bằng {usedModel} (khóa này không dùng được {cfg.Model} — nên đổi model)");
        }
        catch (AiApiException ex) when (ex.IsQuotaError)
        {
            GeminiKeyPool.MarkExhausted(key, TimeSpan.FromMinutes(15));
            return new(index, masked, "quota", "Khóa đúng nhưng tạm hết lượt");
        }
        catch (AiApiException ex) when (ex.IsAuthError)
        {
            GeminiKeyPool.MarkExhausted(key, TimeSpan.FromHours(6));
            return new(index, masked, "invalid", "Khóa sai / hết hạn / không có quyền");
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            return new(index, masked, "timeout",
                $"Google chưa trả lời trong {Budget.TotalSeconds:0} giây (model đang quá tải) — thử lại sau");
        }
        catch (Exception ex) when (ex is AiApiException or InvalidOperationException or HttpRequestException or TaskCanceledException)
        {
            return new(index, masked, "error", ex.Message);
        }
    }

    /// <summary>«Khóa 1 AIza****abcd: Hoạt động · Khóa 2 …: Tạm hết lượt».</summary>
    public static string Detail(IReadOnlyList<KeyResult> r) =>
        string.Join(" · ", r.Select(x => $"Khóa {x.Index} {x.Key}: {x.Message}"));

    public static string Summary(IReadOnlyList<KeyResult> r)
    {
        var ok = r.Count(x => x.Status == "ok");
        if (ok > 0)
            return $"{ok}/{r.Count} khóa hoạt động — khóa hết lượt sẽ tự chuyển sang khóa kế tiếp.";
        var quota = r.Count(x => x.Status == "quota");
        if (quota > 0)
            return $"{quota}/{r.Count} khóa đúng nhưng đang hết lượt — thử lại sau.";
        var timeout = r.Count(x => x.Status == "timeout");
        return timeout > 0
            ? $"Chưa kiểm tra xong {timeout}/{r.Count} khóa — Google đang quá tải, thử lại sau."
            : $"Không khóa nào dùng được ({r.Count} khóa).";
    }
}

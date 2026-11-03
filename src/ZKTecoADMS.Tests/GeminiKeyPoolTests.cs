using Xunit;
using ZKTecoADMS.Api.Services;

namespace ZKTecoADMS.Tests;

public class GeminiKeyPoolTests
{
    const string A = "AIzaAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA1";
    const string B = "AIzaBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB2";
    const string C = "AIzaCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC3";

    [Fact]
    public void Parses_one_key_per_line_comma_or_semicolon_and_drops_duplicates()
    {
        Assert.Equal([A, B, C], GeminiKeyPool.Parse($" {A}\r\n{B}, {C};{A}\n\nshort"));
    }

    [Fact]
    public void Merge_appends_replaces_removes_and_ignores_masked_input()
    {
        var existing = GeminiKeyPool.Join([A, B]);
        // Thêm vào danh sách.
        Assert.Equal(GeminiKeyPool.Join([A, B, C]), GeminiKeyPool.Merge(existing, C, append: true, null));
        // Thay toàn bộ.
        Assert.Equal(C, GeminiKeyPool.Merge(existing, C, append: false, null));
        // Xóa theo mặt nạ hiển thị.
        Assert.Equal(B, GeminiKeyPool.Merge(existing, null, append: true, [GeminiKeyPool.Mask(A)]));
        // Mặt nạ gửi lại / không đổi → null (giữ nguyên, không ghi đè khóa thật bằng dấu *).
        Assert.Null(GeminiKeyPool.Merge(existing, GeminiKeyPool.Mask(A), append: false, null));
        Assert.Null(GeminiKeyPool.Merge(existing, "", append: false, null));
    }

    [Fact]
    public void Exhausted_keys_are_tried_last()
    {
        var keys = new[] { "AIzaKEY1xxxxxxxxxxxxxxxxxxxxxxxxxxxx" + Guid.NewGuid().ToString("N")[..4],
                           "AIzaKEY2xxxxxxxxxxxxxxxxxxxxxxxxxxxx" + Guid.NewGuid().ToString("N")[..4],
                           "AIzaKEY3xxxxxxxxxxxxxxxxxxxxxxxxxxxx" + Guid.NewGuid().ToString("N")[..4] };
        GeminiKeyPool.MarkExhausted(keys[0], TimeSpan.FromMinutes(5));
        Assert.Equal([1, 2, 0], GeminiKeyPool.OrderForUse(keys));
        Assert.True(GeminiKeyPool.IsCoolingDown(keys[0]));
        Assert.False(GeminiKeyPool.IsCoolingDown(keys[1]));
    }
    [Fact]
    public void Het_luot_mot_model_khong_lam_nghi_khoa_cho_model_khac()
    {
        var a = "AIzaKEYAxxxxxxxxxxxxxxxxxxxxxxxxxxxx" + Guid.NewGuid().ToString("N")[..4];
        var b = "AIzaKEYBxxxxxxxxxxxxxxxxxxxxxxxxxxxx" + Guid.NewGuid().ToString("N")[..4];
        // Khóa A hết lượt giọng đọc (TTS) → lời gọi TTS thử khóa B trước, chat vẫn dùng khóa A.
        GeminiKeyPool.MarkExhausted(a + "#gemini-tts", TimeSpan.FromMinutes(5));
        Assert.Equal([1, 0], GeminiKeyPool.OrderForUse([a + "#gemini-tts", b + "#gemini-tts"]));
        Assert.Equal([0, 1], GeminiKeyPool.OrderForUse([a, b]));
    }

    [Fact]
    public void Gioi_han_theo_phut_chi_nghi_dung_khoang_google_goi_y()
    {
        // Gói miễn phí: 429 kèm RetryInfo vài chục giây — trước đây nghỉ 15 phút nên mọi khóa nhanh chóng «nghỉ», trợ lý báo bận.
        const string perMinute = """
            {"error":{"code":429,"status":"RESOURCE_EXHAUSTED","details":[
              {"@type":"type.googleapis.com/google.rpc.QuotaFailure","violations":[{"quotaId":"GenerateRequestsPerMinutePerProjectPerModel-FreeTier"}]},
              {"@type":"type.googleapis.com/google.rpc.RetryInfo","retryDelay":"17s"}]}}
            """;
        var ex = GeminiAiService.ApiError(System.Net.HttpStatusCode.TooManyRequests, perMinute);
        Assert.True(ex.IsQuotaError);
        Assert.False(ex.DailyQuota);
        Assert.Equal(TimeSpan.FromSeconds(17), ex.RetryAfter);
        Assert.Equal(TimeSpan.FromSeconds(17), TenantScopedGeminiAiService.QuotaCooldown(ex));

        var daily = GeminiAiService.ApiError(System.Net.HttpStatusCode.TooManyRequests,
            perMinute.Replace("PerMinute", "PerDay"));
        Assert.True(daily.DailyQuota);
        Assert.Equal(TimeSpan.FromMinutes(15), TenantScopedGeminiAiService.QuotaCooldown(daily));
        Assert.Equal(TimeSpan.FromMinutes(1),
            TenantScopedGeminiAiService.QuotaCooldown(new AiApiException(GeminiAiService.QuotaMessage, 429)));
    }

    [Fact]
    public void Loi_tam_cua_google_chuyen_khoa_khong_phat()
    {
        Assert.True(TenantScopedGeminiAiService.IsTransient(new AiApiException("x", 503)));
        Assert.True(TenantScopedGeminiAiService.IsTransient(new AiApiException("x", 500)));
        Assert.True(TenantScopedGeminiAiService.IsTransient(new HttpRequestException("reset")));
        Assert.True(TenantScopedGeminiAiService.IsTransient(new IOException("stream cut")));
        Assert.True(TenantScopedGeminiAiService.IsTransient(new TaskCanceledException("t", new TimeoutException())));
        Assert.False(TenantScopedGeminiAiService.IsTransient(new TaskCanceledException()));
        Assert.False(TenantScopedGeminiAiService.IsTransient(new AiApiException("x", 400)));
    }

    [Fact]
    public void Bao_loi_lenh_lap_phieu_khong_khuyen_xem_bao_cao()
    {
        var quota = new AiApiException(GeminiAiService.QuotaMessage, 429);
        var action = ZKTecoADMS.Api.Controllers.AiAssistantController.AiFailureReply(quota, action: true);
        Assert.Contains("Chưa lập / sửa gì cả", action);
        Assert.DoesNotContain("Báo cáo", action);
        Assert.Contains("Báo cáo", ZKTecoADMS.Api.Controllers.AiAssistantController.AiFailureReply(new IOException(), action: false));
    }
}

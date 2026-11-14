using System.Text.Json;
using Xunit;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Tests.Pos;

/// <summary>
/// Đếm token Gemini: bóc usageMetadata của Google và cộng lại theo ngày / tính năng / model cho từng cửa hàng.
/// </summary>
[Collection("pos-pg")]
public class GeminiUsageTests(PosPgFixture fx) : PosFlowTestBase(fx)
{
    static GeminiUsageController Ctl(ZKTecoADMS.Infrastructure.ZKTecoDbContext db, Guid store) =>
        PosPgFixture.As(new GeminiUsageController(db), store);

    static JsonElement Json(string s) => JsonDocument.Parse(s).RootElement.Clone();

    [Fact]
    public void Boc_usageMetadata_cua_Google()
    {
        // Câu trả lời thật của gemini-flash-latest: phần lớn token là «suy nghĩ», không nằm trong câu trả lời.
        var u = GeminiUsage.From(Json("""
            {"candidates":[{"content":{"parts":[{"text":"OK"}]}}],
             "usageMetadata":{"promptTokenCount":7,"candidatesTokenCount":1,"totalTokenCount":122,
                              "thoughtsTokenCount":114,"serviceTier":"standard"},
             "modelVersion":"gemini-2.5-flash"}
            """), "gemini-flash-latest");
        Assert.NotNull(u);
        Assert.Equal("gemini-2.5-flash", u!.Model);
        Assert.Equal(7, u.PromptTokens);
        Assert.Equal(1, u.AnswerTokens);
        Assert.Equal(114, u.ThoughtTokens);
        Assert.Equal(122, u.Total);

        // Model không bật suy nghĩ: thiếu hẳn thoughtsTokenCount, vẫn phải đọc được.
        var lite = GeminiUsage.From(Json("""
            {"usageMetadata":{"promptTokenCount":33,"candidatesTokenCount":9,"totalTokenCount":42}}
            """), "gemini-flash-lite-latest");
        Assert.NotNull(lite);
        Assert.Equal("gemini-flash-lite-latest", lite!.Model);
        Assert.Equal(0, lite.ThoughtTokens);
        Assert.Equal(42, lite.Total);

        // Thiếu totalTokenCount → tự cộng, đừng để mất số liệu.
        Assert.Equal(12, GeminiUsage.From(Json("""
            {"usageMetadata":{"promptTokenCount":5,"candidatesTokenCount":7}}
            """), "m")!.Total);

        // Không có usageMetadata (câu trả lời hỏng, đoạn SSE đầu) → bỏ qua, không được ném lỗi.
        Assert.Null(GeminiUsage.From(Json("""{"candidates":[]}"""), "m"));
        Assert.Null(GeminiUsage.From(Json("""{"usageMetadata":{}}"""), "m"));
        Assert.Null(GeminiUsage.From(Json("[]"), "m"));
    }

    [Fact]
    public void Khoang_ngay_mac_dinh_30_ngay_va_chan_khoang_qua_dai()
    {
        var (fromVn, toVn, fromUtc, toUtc) = GeminiUsageController.Range(null, null);
        Assert.Equal(29, (toVn - fromVn).TotalDays);
        // Cận UTC phải lùi 7 giờ so với 00:00 giờ VN.
        Assert.Equal(fromVn.AddHours(-VnTimeHelper.OffsetHours), fromUtc);
        Assert.Equal(toVn.AddDays(1).AddHours(-VnTimeHelper.OffsetHours), toUtc);

        // Xin 3 năm thì cắt còn tối đa cho phép, không quét cả bảng.
        var far = GeminiUsageController.Range(new DateTime(2023, 1, 1), new DateTime(2026, 1, 1));
        Assert.Equal(GeminiUsageController.MaxDays - 1, (far.ToVn - far.FromVn).TotalDays);

        // Gõ ngược from/to vẫn ra khoảng đúng chiều.
        var swapped = GeminiUsageController.Range(new DateTime(2026, 3, 10), new DateTime(2026, 3, 1));
        Assert.Equal(new DateTime(2026, 3, 1), swapped.FromVn);
        Assert.Equal(new DateTime(2026, 3, 10), swapped.ToVn);
    }

    [Fact]
    public async Task Bao_cao_cong_dung_theo_ngay_tinh_nang_model_va_khong_lan_cua_hang()
    {
        if (NoDb) return;
        var storeA = await Fx.NewStoreAsync();
        var storeB = await Fx.NewStoreAsync();
        var today = VnTimeHelper.NowVn().Date;

        await using (var db = Fx.NewDb())
        {
            db.GeminiUsageLogs.AddRange(
                Row(storeA, "/api/ai/assistant/chat", "gemini-flash-latest", today, 10, 5, 100),
                Row(storeA, "/api/ai/assistant/chat", "gemini-flash-latest", today, 10, 5, 50),
                Row(storeA, "/api/pos/ai/menu/scan", "gemini-flash-lite-latest", today.AddDays(-1), 20, 10, 400),
                // Cửa hàng khác không được lẫn vào báo cáo của A.
                Row(storeB, "/api/ai/assistant/chat", "gemini-flash-latest", today, 1, 1, 9999),
                // Ngoài khoảng xem (quá 30 ngày) — phải bị loại.
                Row(storeA, "/api/ai/assistant/chat", "gemini-flash-latest", today.AddDays(-40), 1, 1, 7777));
            await db.SaveChangesAsync();
        }

        await using (var db = Fx.NewDb())
        {
            var r = Data(await Ctl(db, storeA).Get(null, null, default));
            Assert.Equal(3, r.Totals.Calls);
            Assert.Equal(550, r.Totals.TotalTokens);
            Assert.Equal(40, r.Totals.PromptTokens);
            Assert.Equal(20, r.Totals.AnswerTokens);

            // Theo ngày: hai ngày, xếp từ cũ tới mới.
            Assert.Equal(2, r.ByDay.Count);
            Assert.Equal(today.AddDays(-1).ToString("yyyy-MM-dd"), r.ByDay[0].Key);
            Assert.Equal(400, r.ByDay[0].TotalTokens);
            Assert.Equal(today.ToString("yyyy-MM-dd"), r.ByDay[1].Key);
            Assert.Equal(150, r.ByDay[1].TotalTokens);

            // Theo tính năng: tốn nhất lên đầu để biết ngay chỗ nào ngốn token.
            Assert.Equal("/api/pos/ai/menu/scan", r.ByFeature[0].Key);
            Assert.Equal(400, r.ByFeature[0].TotalTokens);
            Assert.Equal("/api/ai/assistant/chat", r.ByFeature[1].Key);
            Assert.Equal(2, r.ByFeature[1].Calls);

            Assert.Equal(2, r.ByModel.Count);
            Assert.Equal("gemini-flash-lite-latest", r.ByModel[0].Key);
        }

        await using (var db = Fx.NewDb())
        {
            var b = Data(await Ctl(db, storeB).Get(null, null, default));
            Assert.Equal(1, b.Totals.Calls);
            Assert.Equal(9999, b.Totals.TotalTokens);
        }
    }

    static GeminiUsageLog Row(Guid store, string feature, string model, DateTime dayVn,
        int prompt, int answer, int total) => new()
        {
            Id = Guid.NewGuid(),
            StoreId = store,
            Feature = feature,
            Model = model,
            ApiKeyMask = "AIza****abcd",
            PromptTokens = prompt,
            AnswerTokens = answer,
            ThoughtTokens = total - prompt - answer,
            TotalTokens = total,
            // 10:00 giờ VN của ngày đó → 03:00 UTC, vẫn phải rơi đúng ngày VN khi gom nhóm.
            CreatedAt = dayVn.AddHours(10 - VnTimeHelper.OffsetHours),
        };
}

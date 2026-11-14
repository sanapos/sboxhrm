using System.Text.Json;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Số token của MỘT lời gọi Gemini, lấy từ <c>usageMetadata</c> trong câu trả lời của Google.
/// Token «suy nghĩ» (<see cref="ThoughtTokens"/>) thường chiếm phần lớn mà không nằm trong câu trả lời,
/// nên không đếm riêng thì không biết thật sự tốn bao nhiêu.
/// </summary>
public sealed record GeminiUsage(
    string Model,
    int PromptTokens,
    int AnswerTokens,
    int ThoughtTokens,
    int TotalTokens)
{
    /// <summary>Google thỉnh thoảng thiếu totalTokenCount — tự cộng để không mất số liệu.</summary>
    public int Total => TotalTokens > 0 ? TotalTokens : PromptTokens + AnswerTokens + ThoughtTokens;

    /// <summary>
    /// Bóc <c>usageMetadata</c> từ thân câu trả lời (generateContent và cả từng đoạn SSE). Trả null khi
    /// không có — câu trả lời hỏng hoặc đoạn SSE chưa kèm số liệu, lúc đó bỏ qua chứ không được ném lỗi.
    /// </summary>
    public static GeminiUsage? From(JsonElement root, string fallbackModel)
    {
        if (root.ValueKind != JsonValueKind.Object
            || !root.TryGetProperty("usageMetadata", out var u)
            || u.ValueKind != JsonValueKind.Object)
            return null;

        var usage = new GeminiUsage(
            Model: root.TryGetProperty("modelVersion", out var m) && m.ValueKind == JsonValueKind.String
                ? m.GetString() ?? fallbackModel
                : fallbackModel,
            PromptTokens: Int(u, "promptTokenCount"),
            AnswerTokens: Int(u, "candidatesTokenCount"),
            ThoughtTokens: Int(u, "thoughtsTokenCount"),
            TotalTokens: Int(u, "totalTokenCount"));

        // Đoạn SSE đầu tiên có usageMetadata rỗng — không ghi dòng 0 token.
        return usage.Total > 0 ? usage : null;
    }

    static int Int(JsonElement o, string name) =>
        o.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.Number && v.TryGetInt32(out var i) ? i : 0;
}

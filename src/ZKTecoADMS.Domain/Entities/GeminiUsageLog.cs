using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Mỗi lời gọi Gemini là một dòng: cửa hàng nào, tính năng nào, model nào, khóa nào (đã che), tốn bao nhiêu token.
/// Dùng để biết cửa hàng nào tiêu nhiều, tính năng nào tốn nhất và đặt hạn mức — trước đây không đếm gì cả.
/// Chỉ ghi thêm, không sửa; khóa API **không bao giờ** lưu nguyên mà chỉ lưu dạng che AIza****abcd.
/// </summary>
public class GeminiUsageLog : Entity<Guid>
{
    /// <summary>Cửa hàng gọi AI. Null = lời gọi chạy nền / của Super Admin không thuộc cửa hàng nào.</summary>
    public Guid? StoreId { get; set; }

    /// <summary>Tính năng gọi AI — lấy theo đường dẫn API, ví dụ «/api/ai/assistant/chat».</summary>
    [MaxLength(120)]
    public string Feature { get; set; } = string.Empty;

    [MaxLength(60)]
    public string Model { get; set; } = string.Empty;

    /// <summary>Khóa đã che (GeminiKeyPool.Mask) — để biết khóa nào đang gánh phần lớn lưu lượng.</summary>
    [MaxLength(80)]
    public string? ApiKeyMask { get; set; }

    /// <summary>Khóa AI dùng chung của SBOX (AppSettings StoreId = null) chứ không phải khóa riêng cửa hàng.</summary>
    public bool SharedKey { get; set; }

    public int PromptTokens { get; set; }

    public int AnswerTokens { get; set; }

    /// <summary>Token «suy nghĩ» — không nằm trong câu trả lời nhưng vẫn tính tiền.</summary>
    public int ThoughtTokens { get; set; }

    public int TotalTokens { get; set; }
}

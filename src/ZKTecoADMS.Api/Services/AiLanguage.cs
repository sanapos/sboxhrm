namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Ngôn ngữ giao diện của người dùng (vi / en / ko / ja / zh) → ngôn ngữ trợ lý trả lời, chép lời, đọc.
/// Dữ liệu cửa hàng (tên hàng, tên người, nhóm hàng…) giữ nguyên như đã nhập.
/// </summary>
public static class AiLanguage
{
    public const string Vietnamese = "vi";

    static readonly Dictionary<string, (string Vi, string Native)> Names = new()
    {
        ["vi"] = ("tiếng Việt", "Tiếng Việt"),
        ["en"] = ("tiếng Anh", "English"),
        ["ko"] = ("tiếng Hàn", "한국어"),
        ["ja"] = ("tiếng Nhật", "日本語"),
        ["zh"] = ("tiếng Trung giản thể", "简体中文"),
    };

    /// <summary>Mã chuẩn; lạ / trống → tiếng Việt. Nhận cả "en-US", "zh_CN".</summary>
    public static string Normalize(string? code)
    {
        var c = (code ?? "").Trim().ToLowerInvariant();
        if (c.Length > 2) c = c[..2];
        return Names.ContainsKey(c) ? c : Vietnamese;
    }

    public static bool IsVietnamese(string? code) => Normalize(code) == Vietnamese;

    /// <summary>Tên ngôn ngữ viết bằng tiếng Việt (dùng trong chỉ dẫn cho AI) + tên bản địa.</summary>
    public static string Describe(string? code)
    {
        var n = Names[Normalize(code)];
        return n.Vi == n.Native ? n.Vi : $"{n.Vi} ({n.Native})";
    }

    /// <summary>Quy tắc ngôn ngữ trả lời cho system prompt.</summary>
    public static string AnswerRule(string? code) => IsVietnamese(code)
        ? "Trả lời bằng tiếng Việt."
        : $"Người dùng dùng giao diện {Describe(code)}: LUÔN trả lời bằng {Describe(code)} (kể cả khi dữ liệu / hướng dẫn bên dưới "
          + "viết tiếng Việt). Giữ NGUYÊN tên riêng, tên hàng, tên nhân viên, tên menu / màn hình như trong dữ liệu; số tiền ghi kèm «đ» (VND).";
}

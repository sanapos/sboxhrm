using System.Text;
using System.Text.RegularExpressions;

namespace ZKTecoADMS.Application.Services;

/// <summary>
/// Mã cửa hàng (mã doanh nghiệp) — dùng để đăng nhập: chuẩn hoá từ tên, từ khoá cấm, gợi ý mã còn trống.
/// </summary>
public static class StoreCodeRules
{
    public const int MinLength = 2, MaxLength = 20;

    /// <summary>Mã trùng đường dẫn / vai trò hệ thống — không cho đăng ký.</summary>
    public static readonly HashSet<string> Reserved = new(StringComparer.OrdinalIgnoreCase)
    {
        "admin", "superadmin", "api", "www", "app", "sbox", "root", "system", "support", "help", "login",
        "register", "test", "demo", "agent", "daily", "store", "shop", "null", "undefined",
    };

    /// <summary>Bỏ dấu tiếng Việt, về chữ thường, chỉ giữ a-z0-9, cắt 20 ký tự.</summary>
    public static string Sanitize(string? input)
    {
        if (string.IsNullOrWhiteSpace(input)) return string.Empty;
        var s = RemoveAccents(input.Trim().ToLowerInvariant());
        s = Regex.Replace(s, "[^a-z0-9]", "");
        return s.Length > MaxLength ? s[..MaxLength] : s;
    }

    public static string RemoveAccents(string text)
    {
        var normalized = text.Replace('đ', 'd').Replace('Đ', 'D').Normalize(NormalizationForm.FormD);
        var sb = new StringBuilder(normalized.Length);
        foreach (var c in normalized)
            if (System.Globalization.CharUnicodeInfo.GetUnicodeCategory(c) != System.Globalization.UnicodeCategory.NonSpacingMark)
                sb.Append(c);
        return sb.ToString().Normalize(NormalizationForm.FormC);
    }

    /// <summary>Lỗi định dạng (null = hợp lệ).</summary>
    public static string? FormatError(string code)
    {
        if (code.Length < MinLength) return $"Mã cần ít nhất {MinLength} ký tự.";
        if (code.Length > MaxLength) return $"Mã tối đa {MaxLength} ký tự.";
        if (!Regex.IsMatch(code, "^[a-z0-9]+$")) return "Mã chỉ gồm chữ thường không dấu và số (a-z, 0-9).";
        if (Reserved.Contains(code)) return "Mã này được hệ thống giữ lại, vui lòng chọn mã khác.";
        return null;
    }

    /// <summary>
    /// Gợi ý mã còn trống từ mã gốc / tên cửa hàng: viết tắt tên, gốc + số, gốc + tỉnh...
    /// <paramref name="isTaken"/> kiểm tra trùng (đã chuẩn hoá chữ thường).
    /// </summary>
    public static List<string> Suggest(string baseCode, string? storeName, string? province, Func<string, bool> isTaken,
        int max = 3)
    {
        var candidates = new List<string>();
        void Add(string? c)
        {
            c = Sanitize(c);
            if (c.Length >= MinLength && FormatError(c) == null && !candidates.Contains(c)) candidates.Add(c);
        }

        var root = Sanitize(baseCode);
        if (root.Length < MinLength) root = Sanitize(storeName);
        // Viết tắt chữ cái đầu mỗi từ của tên: «Cà phê Mộc Nhiên» → «cpmn»
        var words = RemoveAccents((storeName ?? "").ToLowerInvariant())
            .Split(' ', StringSplitOptions.RemoveEmptyEntries)
            .Select(w => Regex.Replace(w, "[^a-z0-9]", ""))
            .Where(w => w.Length > 0)
            .ToList();
        var initials = string.Concat(words.Select(w => w[0]));
        var provinceCode = Sanitize(province);

        Add(root);
        if (words.Count > 1) Add(initials + (words.Count > 0 ? words[^1] : ""));
        if (provinceCode.Length > 0) Add((root.Length > 12 ? root[..12] : root) + provinceCode[..Math.Min(6, provinceCode.Length)]);
        for (var i = 1; i <= 99 && candidates.Count < 20; i++)
            Add((root.Length > 17 ? root[..17] : root) + i);
        if (initials.Length >= 2)
            for (var i = 1; i <= 9; i++) Add(initials + i);

        return candidates.Where(c => !isTaken(c)).Take(max).ToList();
    }
}

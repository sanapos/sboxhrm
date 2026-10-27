using System.Globalization;
using System.Text;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// So tên hàng khi nhập menu / Excel. Trùng chắc chắn chỉ khi giống hệt (NFC, không phân biệt hoa thường,
/// gộp khoảng trắng) — «Bánh mì bơ» ≠ «Bánh mì bò». Bỏ dấu chỉ dùng để cảnh báo «có thể trùng» hoặc tra cứu mềm.
/// </summary>
public static class PosProductNameMatch
{
    /// <summary>Khóa trùng chắc chắn: NFC + chữ thường + gộp khoảng trắng (giữ dấu, giữ ký tự).</summary>
    public static string ExactKey(string? s)
    {
        if (string.IsNullOrWhiteSpace(s)) return "";
        var t = s.Normalize(NormalizationForm.FormC).ToLowerInvariant();
        var sb = new StringBuilder(t.Length);
        var space = false;
        foreach (var ch in t.Trim())
        {
            if (char.IsWhiteSpace(ch))
            {
                space = true;
                continue;
            }
            if (space && sb.Length > 0) sb.Append(' ');
            space = false;
            sb.Append(ch);
        }
        return sb.ToString();
    }

    /// <summary>Khóa mềm: bỏ dấu, bỏ ký tự không phải chữ / số (đ → d).</summary>
    public static string FoldKey(string? s)
    {
        if (string.IsNullOrWhiteSpace(s)) return "";
        var sb = new StringBuilder();
        foreach (var ch in s.Trim().ToLowerInvariant().Normalize(NormalizationForm.FormD))
        {
            if (CharUnicodeInfo.GetUnicodeCategory(ch) == UnicodeCategory.NonSpacingMark) continue;
            var c = ch == 'đ' ? 'd' : ch;
            if (char.IsLetterOrDigit(c)) sb.Append(c);
        }
        return sb.ToString();
    }

    /// <summary>Tên viết không dấu (menu gõ «Ca phe sua») — khi đó mới so bỏ dấu.</summary>
    public static bool HasNoDiacritics(string? s) =>
        !string.IsNullOrWhiteSpace(s) && FoldKey(s) == LettersDigits(s);

    static string LettersDigits(string s)
    {
        var sb = new StringBuilder();
        foreach (var ch in s.Trim().ToLowerInvariant().Normalize(NormalizationForm.FormC))
            if (char.IsLetterOrDigit(ch)) sb.Append(ch);
        return sb.ToString();
    }

    static List<string> Tokens(string s, bool fold)
    {
        var t = fold
            ? s.ToLowerInvariant().Normalize(NormalizationForm.FormD)
            : s.ToLowerInvariant().Normalize(NormalizationForm.FormC);
        var list = new List<string>();
        var sb = new StringBuilder();
        foreach (var ch in t)
        {
            if (fold && CharUnicodeInfo.GetUnicodeCategory(ch) == UnicodeCategory.NonSpacingMark) continue;
            var c = fold && ch == 'đ' ? 'd' : ch;
            if (char.IsLetterOrDigit(c))
            {
                sb.Append(c);
                continue;
            }
            if (sb.Length > 0) list.Add(sb.ToString());
            sb.Clear();
        }
        if (sb.Length > 0) list.Add(sb.ToString());
        return list;
    }

    /// <summary>
    /// Hai tên cùng là một món (dùng để nhận món mẫu AI chọn): giống hệt; hoặc các từ của tên ngắn (≥ 2 từ)
    /// đều có trong tên dài; hoặc trùng ≥ 75% số từ. Giữ dấu khi so (trừ khi một bên viết không dấu).
    /// </summary>
    public static bool SameDish(string? a, string? b)
    {
        if (string.IsNullOrWhiteSpace(a) || string.IsNullOrWhiteSpace(b)) return false;
        if (ExactKey(a) == ExactKey(b)) return true;
        var fold = HasNoDiacritics(a) || HasNoDiacritics(b);
        if (fold && FoldKey(a) == FoldKey(b)) return true;
        var ta = Tokens(a, fold).ToHashSet();
        var tb = Tokens(b, fold).ToHashSet();
        if (ta.Count == 0 || tb.Count == 0) return false;
        var (small, large) = ta.Count <= tb.Count ? (ta, tb) : (tb, ta);
        var common = small.Count(large.Contains);
        if (small.Count >= 2 && common == small.Count) return true;
        var union = ta.Count + tb.Count - common;
        return union > 0 && common * 4 >= union * 3;
    }
}

using System.Text;

namespace ZKTecoADMS.Application.Helpers;

/// <summary>
/// Tìm kiếm tiếng Việt không phân biệt dấu / hoa thường: «binh» khớp «Bình», «banh mi» khớp «Bánh mì».
/// <see cref="Fold"/> chạy được cả trong LINQ-to-SQL (dịch thành <c>translate(lower(x), …)</c>, không cần extension)
/// lẫn trong bộ nhớ (đăng ký dịch SQL ở Infrastructure.VnSearchEf).
/// </summary>
public static class VnSearch
{
    public const string From = "àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ"
                      + "ÀÁẠẢÃÂẦẤẬẨẪĂẰẮẶẲẴÈÉẸẺẼÊỀẾỆỂỄÌÍỊỈĨÒÓỌỎÕÔỒỐỘỔỖƠỜỚỢỞỠÙÚỤỦŨƯỪỨỰỬỮỲÝỴỶỸĐ";
    public const string To = "aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd"
                    + "aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd";

    /// <summary>Dấu tổ hợp (bàn phím gõ tách dấu) — SQL translate bỏ hẳn các ký tự này.</summary>
    public const string Combining = "̛̣̀́̃̉̂̆";

    static readonly Dictionary<char, char> Map = BuildMap();

    static Dictionary<char, char> BuildMap()
    {
        var m = new Dictionary<char, char>();
        for (var i = 0; i < From.Length; i++) m[From[i]] = To[i];
        return m;
    }

    /// <summary>Bỏ dấu + chữ thường. Trong truy vấn EF được dịch sang SQL.</summary>
    public static string Fold(string? text)
    {
        if (string.IsNullOrEmpty(text)) return "";
        text = text.Normalize(NormalizationForm.FormC);
        var sb = new StringBuilder(text.Length);
        foreach (var ch in text)
        {
            if (Combining.IndexOf(ch) >= 0) continue;
            var c = Map.TryGetValue(ch, out var r) ? r : char.ToLowerInvariant(ch);
            sb.Append(Map.TryGetValue(c, out var r2) ? r2 : c);
        }
        return sb.ToString();
    }

    /// <summary>
    /// «text chứa term» không dấu. <paramref name="foldedTerm"/> phải là kết quả của <see cref="FoldText"/>.
    /// Trong truy vấn EF dịch thành <c>translate(lower(x),…) LIKE '%term%'</c> — dùng được chỉ mục GIN pg_trgm
    /// (khác <c>Fold(x).Contains(s)</c> bị dịch thành strpos, luôn quét cả bảng).
    /// </summary>
    public static bool Has(string? text, string foldedTerm) => Fold(text).Contains(foldedTerm);

    /// <summary>Chuẩn hóa từ khóa người dùng gõ (trim + bỏ dấu + thường).</summary>
    public static string FoldText(string? text) => Fold(text?.Trim());
}

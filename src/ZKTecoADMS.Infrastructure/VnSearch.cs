using System.Linq.Expressions;
using System.Text;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Query.SqlExpressions;

namespace ZKTecoADMS.Infrastructure;

/// <summary>
/// Tìm kiếm tiếng Việt không phân biệt dấu / hoa thường: «binh» khớp «Bình», «banh mi» khớp «Bánh mì».
/// <see cref="Fold"/> chạy được cả trong LINQ-to-SQL (dịch thành <c>translate(lower(x), …)</c>, không cần extension)
/// lẫn trong bộ nhớ.
/// </summary>
public static class VnSearch
{
    const string From = "àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ"
                      + "ÀÁẠẢÃÂẦẤẬẨẪĂẰẮẶẲẴÈÉẸẺẼÊỀẾỆỂỄÌÍỊỈĨÒÓỌỎÕÔỒỐỘỔỖƠỜỚỢỞỠÙÚỤỦŨƯỪỨỰỬỮỲÝỴỶỸĐ";
    const string To = "aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd"
                    + "aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd";

    /// <summary>Dấu tổ hợp (bàn phím gõ tách dấu) — SQL translate bỏ hẳn các ký tự này.</summary>
    const string Combining = "̛̣̀́̃̉̂̆";

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

    /// <summary>Chuẩn hóa từ khóa người dùng gõ (trim + bỏ dấu + thường).</summary>
    public static string FoldText(string? text) => Fold(text?.Trim());

    internal static void Register(ModelBuilder modelBuilder)
    {
        var method = typeof(VnSearch).GetMethod(nameof(Fold), [typeof(string)])!;
        modelBuilder.HasDbFunction(method).HasTranslation(args =>
        {
            var arg = args[0];
            var tm = arg.TypeMapping;
            var lower = new SqlFunctionExpression("lower", [arg], nullable: true, argumentsPropagateNullability: [true], typeof(string), tm);
            return new SqlFunctionExpression(
                "translate",
                [lower, new SqlConstantExpression(Expression.Constant(From + Combining), tm), new SqlConstantExpression(Expression.Constant(To), tm)],
                nullable: true,
                argumentsPropagateNullability: [true, false, false],
                typeof(string),
                tm);
        });
    }
}

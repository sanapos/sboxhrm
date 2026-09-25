using System.Text;

namespace ZKTecoADMS.Infrastructure.Helpers;

/// <summary>
/// Tách script PostgreSQL thành từng câu theo dấu <c>;</c> — bỏ qua <c>;</c> nằm trong
/// chuỗi <c>'...'</c>, định danh <c>"..."</c>, khối dollar-quote (<c>$$...$$</c>, <c>$tag$...$tag$</c>)
/// và comment (<c>--</c>, <c>/* */</c>). Comment bị loại khỏi câu trả về.
/// </summary>
public static class SqlScriptSplitter
{
    public static List<string> Split(string sql)
    {
        var result = new List<string>();
        var sb = new StringBuilder();
        var i = 0;
        while (i < sql.Length)
        {
            var c = sql[i];
            var next = i + 1 < sql.Length ? sql[i + 1] : '\0';

            if (c == '-' && next == '-')
            {
                while (i < sql.Length && sql[i] != '\n') i++;
                continue;
            }
            if (c == '/' && next == '*')
            {
                var end = sql.IndexOf("*/", i + 2, StringComparison.Ordinal);
                i = end < 0 ? sql.Length : end + 2;
                sb.Append(' ');
                continue;
            }
            if (c is '\'' or '"')
            {
                i = CopyQuoted(sql, i, c, sb);
                continue;
            }
            if (c == '$' && TryReadDollarTag(sql, i, out var tag))
            {
                var close = sql.IndexOf(tag, i + tag.Length, StringComparison.Ordinal);
                var stop = close < 0 ? sql.Length : close + tag.Length;
                sb.Append(sql, i, stop - i);
                i = stop;
                continue;
            }
            if (c == ';')
            {
                Flush(sb, result);
                i++;
                continue;
            }
            sb.Append(c);
            i++;
        }
        Flush(sb, result);
        return result;
    }

    /// <summary>Chép chuỗi/định danh tới dấu đóng; cặp dấu nháy đôi (<c>''</c>) là escape.</summary>
    private static int CopyQuoted(string sql, int start, char quote, StringBuilder sb)
    {
        sb.Append(quote);
        var i = start + 1;
        while (i < sql.Length)
        {
            sb.Append(sql[i]);
            if (sql[i] == quote)
            {
                if (i + 1 < sql.Length && sql[i + 1] == quote)
                {
                    sb.Append(quote);
                    i += 2;
                    continue;
                }
                return i + 1;
            }
            i++;
        }
        return i;
    }

    /// <summary><c>$$</c> hoặc <c>$tag$</c> (tag: chữ, số, gạch dưới; không bắt đầu bằng số).</summary>
    private static bool TryReadDollarTag(string sql, int start, out string tag)
    {
        tag = "";
        var i = start + 1;
        while (i < sql.Length && (char.IsLetterOrDigit(sql[i]) || sql[i] == '_'))
        {
            if (i == start + 1 && char.IsDigit(sql[i])) return false; // $1 = tham số, không phải tag
            i++;
        }
        if (i >= sql.Length || sql[i] != '$') return false;
        tag = sql.Substring(start, i - start + 1);
        return true;
    }

    private static void Flush(StringBuilder sb, List<string> result)
    {
        var lines = sb.ToString()
            .Split('\n')
            .Select(l => l.TrimEnd())
            .Where(l => l.Trim().Length > 0);
        var stmt = string.Join('\n', lines).Trim();
        if (stmt.Length > 0) result.Add(stmt);
        sb.Clear();
    }
}

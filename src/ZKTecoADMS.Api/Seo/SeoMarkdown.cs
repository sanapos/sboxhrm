using System.Net;
using System.Text;
using System.Text.RegularExpressions;

namespace ZKTecoADMS.Api.Seo;

/// <summary>
/// Markdown tối giản cho bài viết SEO: ## tiêu đề, đoạn, danh sách (-, 1.), &gt; trích dẫn, bảng |a|b|,
/// **đậm**, *nghiêng*, `mã`, [liên kết](url), ![ảnh](url), --- . Mọi chữ được escape — không cho HTML thô.
/// Liên kết chỉ http(s), /, #, mailto:, tel:.
/// </summary>
public static partial class SeoMarkdown
{
    public record Heading(int Level, string Text, string Id);

    public static string ToHtml(string? markdown) => Render(markdown, out _);

    public static string Render(string? markdown, out List<Heading> headings)
    {
        headings = [];
        var lines = (markdown ?? "").Replace("\r\n", "\n").Replace('\r', '\n').Split('\n');
        var sb = new StringBuilder();
        var para = new List<string>();
        var usedIds = new HashSet<string>();
        int i = 0;

        void FlushPara()
        {
            if (para.Count == 0) return;
            sb.Append("<p>").Append(Inline(string.Join(" ", para))).Append("</p>\n");
            para.Clear();
        }

        while (i < lines.Length)
        {
            var raw = lines[i];
            var line = raw.Trim();
            if (line.Length == 0) { FlushPara(); i++; continue; }

            var h = HeadingRx().Match(line);
            if (h.Success)
            {
                FlushPara();
                var level = Math.Clamp(h.Groups[1].Value.Length, 2, 4); // H1 dành cho tiêu đề bài
                var text = h.Groups[2].Value.Trim();
                var id = UniqueId(Slugify(text), usedIds);
                headings.Add(new Heading(level, text, id));
                sb.Append($"<h{level} id=\"{id}\">{Inline(text)}</h{level}>\n");
                i++;
                continue;
            }

            if (line is "---" or "***")
            {
                FlushPara();
                sb.Append("<hr>\n");
                i++;
                continue;
            }

            if (line.StartsWith('>'))
            {
                FlushPara();
                var quote = new List<string>();
                while (i < lines.Length && lines[i].Trim().StartsWith('>'))
                {
                    quote.Add(lines[i].Trim().TrimStart('>').Trim());
                    i++;
                }
                sb.Append("<blockquote><p>").Append(Inline(string.Join(" ", quote))).Append("</p></blockquote>\n");
                continue;
            }

            if (line.StartsWith('|') && i + 1 < lines.Length && TableSepRx().IsMatch(lines[i + 1].Trim()))
            {
                FlushPara();
                var header = Cells(line);
                i += 2;
                sb.Append("<div class=\"table-wrap\"><table><thead><tr>");
                foreach (var c in header) sb.Append("<th>").Append(Inline(c)).Append("</th>");
                sb.Append("</tr></thead><tbody>\n");
                while (i < lines.Length && lines[i].Trim().StartsWith('|'))
                {
                    sb.Append("<tr>");
                    foreach (var c in Cells(lines[i].Trim())) sb.Append("<td>").Append(Inline(c)).Append("</td>");
                    sb.Append("</tr>\n");
                    i++;
                }
                sb.Append("</tbody></table></div>\n");
                continue;
            }

            var ul = UlRx().Match(line);
            var ol = OlRx().Match(line);
            if (ul.Success || ol.Success)
            {
                FlushPara();
                var ordered = ol.Success;
                sb.Append(ordered ? "<ol>\n" : "<ul>\n");
                while (i < lines.Length)
                {
                    var l = lines[i].Trim();
                    var m = ordered ? OlRx().Match(l) : UlRx().Match(l);
                    if (!m.Success) break;
                    sb.Append("<li>").Append(Inline(m.Groups[1].Value)).Append("</li>\n");
                    i++;
                }
                sb.Append(ordered ? "</ol>\n" : "</ul>\n");
                continue;
            }

            var img = ImageLineRx().Match(line);
            if (img.Success)
            {
                FlushPara();
                var alt = img.Groups[1].Value;
                var src = SafeUrl(img.Groups[2].Value);
                if (src != null)
                {
                    sb.Append("<figure><img src=\"").Append(Attr(src)).Append("\" alt=\"").Append(Attr(alt))
                        .Append("\" loading=\"lazy\">");
                    if (alt.Length > 0) sb.Append("<figcaption>").Append(Enc(alt)).Append("</figcaption>");
                    sb.Append("</figure>\n");
                }
                i++;
                continue;
            }

            para.Add(line);
            i++;
        }
        FlushPara();
        return sb.ToString();
    }

    static List<string> Cells(string row) =>
        row.Trim().Trim('|').Split('|').Select(c => c.Trim()).ToList();

    /// <summary>Định dạng trong dòng: escape trước, rồi thay mẫu (an toàn vì mẫu không chứa &lt; &gt;).</summary>
    public static string Inline(string text)
    {
        var s = Enc(text);
        s = InlineImageRx().Replace(s, m =>
        {
            var url = SafeUrl(WebUtility.HtmlDecode(m.Groups[2].Value));
            return url == null ? m.Value : $"<img src=\"{Attr(url)}\" alt=\"{m.Groups[1].Value}\" loading=\"lazy\">";
        });
        s = LinkRx().Replace(s, m =>
        {
            var url = SafeUrl(WebUtility.HtmlDecode(m.Groups[2].Value));
            if (url == null) return m.Groups[1].Value;
            var external = url.StartsWith("http", StringComparison.OrdinalIgnoreCase)
                && !url.Contains("sboxhrm.com", StringComparison.OrdinalIgnoreCase)
                && !url.Contains("sboxpos.com", StringComparison.OrdinalIgnoreCase);
            return $"<a href=\"{Attr(url)}\"{(external ? " rel=\"noopener\" target=\"_blank\"" : "")}>{m.Groups[1].Value}</a>";
        });
        s = CodeRx().Replace(s, "<code>$1</code>");
        s = BoldRx().Replace(s, "<strong>$1</strong>");
        s = ItalicRx().Replace(s, "<em>$1</em>");
        return s;
    }

    public static string? SafeUrl(string? url)
    {
        var u = (url ?? "").Trim();
        if (u.Length == 0) return null;
        if (u.StartsWith("http://", StringComparison.OrdinalIgnoreCase)
            || u.StartsWith("https://", StringComparison.OrdinalIgnoreCase)
            || u.StartsWith("mailto:", StringComparison.OrdinalIgnoreCase)
            || u.StartsWith("tel:", StringComparison.OrdinalIgnoreCase)
            || (u.StartsWith('/') && !u.StartsWith("//"))
            || u.StartsWith('#'))
            return u;
        return null;
    }

    /// <summary>Chữ thường không dấu, nối gạch — dùng cho slug và id tiêu đề.</summary>
    public static string Slugify(string text)
    {
        var s = (text ?? "").Trim().ToLowerInvariant().Replace('đ', 'd');
        var normalized = s.Normalize(NormalizationForm.FormD);
        var sb = new StringBuilder();
        foreach (var ch in normalized)
        {
            var cat = System.Globalization.CharUnicodeInfo.GetUnicodeCategory(ch);
            if (cat == System.Globalization.UnicodeCategory.NonSpacingMark) continue;
            sb.Append(char.IsLetterOrDigit(ch) && ch < 128 ? ch : '-');
        }
        var slug = MultiDashRx().Replace(sb.ToString(), "-").Trim('-');
        return slug.Length > 120 ? slug[..120].TrimEnd('-') : slug;
    }

    static string UniqueId(string id, HashSet<string> used)
    {
        if (id.Length == 0) id = "muc";
        var candidate = id;
        var n = 2;
        while (!used.Add(candidate)) candidate = $"{id}-{n++}";
        return candidate;
    }

    /// <summary>Chữ thuần (bỏ ký hiệu Markdown) — cho mô tả tự sinh, đếm thời gian đọc.</summary>
    public static string PlainText(string? markdown)
    {
        var s = markdown ?? "";
        s = InlineImageRawRx().Replace(s, "");
        s = LinkRawRx().Replace(s, "$1");
        s = MarkRx().Replace(s, "");
        return MultiSpaceRx().Replace(s, " ").Trim();
    }

    /// <summary>Chỉ escape &amp; &lt; &gt; " ' — giữ nguyên chữ tiếng Việt (WebUtility mã hóa cả á, ê…).</summary>
    public static string Enc(string? s)
    {
        if (string.IsNullOrEmpty(s)) return "";
        var sb = new StringBuilder(s.Length + 16);
        foreach (var ch in s)
        {
            sb.Append(ch switch
            {
                '&' => "&amp;",
                '<' => "&lt;",
                '>' => "&gt;",
                '"' => "&quot;",
                '\'' => "&#39;",
                _ => ch.ToString(),
            });
        }
        return sb.ToString();
    }

    public static string Attr(string? s) => Enc(s);

    [GeneratedRegex(@"^(#{2,4})\s+(.+)$")] private static partial Regex HeadingRx();
    [GeneratedRegex(@"^\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)*\|?$")] private static partial Regex TableSepRx();
    [GeneratedRegex(@"^[-*+]\s+(.+)$")] private static partial Regex UlRx();
    [GeneratedRegex(@"^\d+[.)]\s+(.+)$")] private static partial Regex OlRx();
    [GeneratedRegex(@"^!\[([^\]]*)\]\(([^)\s]+)\)$")] private static partial Regex ImageLineRx();
    [GeneratedRegex(@"!\[([^\]]*)\]\(([^)\s]+)\)")] private static partial Regex InlineImageRx();
    [GeneratedRegex(@"\[([^\]]+)\]\(([^)\s]+)\)")] private static partial Regex LinkRx();
    [GeneratedRegex(@"`([^`]+)`")] private static partial Regex CodeRx();
    [GeneratedRegex(@"\*\*(.+?)\*\*")] private static partial Regex BoldRx();
    [GeneratedRegex(@"(?<![*\w])\*(?!\s)(.+?)(?<!\s)\*(?![*\w])")] private static partial Regex ItalicRx();
    [GeneratedRegex(@"-{2,}")] private static partial Regex MultiDashRx();
    [GeneratedRegex(@"!\[[^\]]*\]\([^)]*\)")] private static partial Regex InlineImageRawRx();
    [GeneratedRegex(@"\[([^\]]+)\]\([^)]*\)")] private static partial Regex LinkRawRx();
    [GeneratedRegex(@"[#>*`|_]+|^-{3,}$|^\s*[-+]\s+|^\s*\d+[.)]\s+", RegexOptions.Multiline)] private static partial Regex MarkRx();
    [GeneratedRegex(@"\s+")] private static partial Regex MultiSpaceRx();
}

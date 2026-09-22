using System.Net;
using System.Text;
using System.Text.RegularExpressions;

namespace ZKTecoADMS.Api.Services;

/// <summary>Ghép {Token} + &lt;!--BEGIN_ITEMS--&gt; giống Flutter renderPosPrintTemplateHtml.</summary>
public static class PosPrintTemplateHtmlRenderer
{
    const string ItemBegin = "<!--BEGIN_ITEMS-->";
    const string ItemEnd = "<!--END_ITEMS-->";

    const string DefaultItemTable =
        "<table style=\"width:100%;border-collapse:collapse;margin:8px 0;font-size:12px\">" +
        "<thead><tr style=\"background:#f3f4f6\">" +
        "<th style=\"border:1px solid #111;padding:4px 2px;text-align:center\">STT</th>" +
        "<th style=\"border:1px solid #111;padding:4px 4px;text-align:left\">Tên hàng</th>" +
        "<th style=\"border:1px solid #111;padding:4px 2px;text-align:center\">ĐVT</th>" +
        "<th style=\"border:1px solid #111;padding:4px 2px;text-align:center\">SL</th>" +
        "<th style=\"border:1px solid #111;padding:4px 3px;text-align:right\">Đơn giá</th>" +
        "<th style=\"border:1px solid #111;padding:4px 3px;text-align:right\">Thành tiền</th>" +
        "<th style=\"border:1px solid #111;padding:4px 2px;text-align:center\">BH</th>" +
        "</tr></thead><tbody>" + ItemBegin +
        "<tr>" +
        "<td style=\"border:1px solid #111;padding:4px 2px;text-align:center\">{STT}</td>" +
        "<td style=\"border:1px solid #111;padding:4px 4px\">{Ten_Hang_Hoa}</td>" +
        "<td style=\"border:1px solid #111;padding:4px 2px;text-align:center\">{Don_Vi_Tinh}</td>" +
        "<td style=\"border:1px solid #111;padding:4px 2px;text-align:center\">{So_Luong}</td>" +
        "<td style=\"border:1px solid #111;padding:4px 3px;text-align:right\">{Don_Gia}</td>" +
        "<td style=\"border:1px solid #111;padding:4px 3px;text-align:right\">{Thanh_Tien}</td>" +
        "<td style=\"border:1px solid #111;padding:4px 2px;text-align:center\">{Bao_Hanh}</td>" +
        "</tr>" + ItemEnd +
        "</tbody></table>";

    static readonly Regex TableRe = new(
        @"<table\b[^>]*>[\s\S]*?</table>",
        RegexOptions.IgnoreCase | RegexOptions.CultureInvariant | RegexOptions.Compiled);

    static readonly Regex TbodyRe = new(
        @"(<tbody\b[^>]*>)([\s\S]*?)(</tbody>)",
        RegexOptions.IgnoreCase | RegexOptions.CultureInvariant | RegexOptions.Compiled);

    static readonly Regex TrRe = new(
        @"<tr\b[^>]*>[\s\S]*?</tr>",
        RegexOptions.IgnoreCase | RegexOptions.CultureInvariant | RegexOptions.Compiled);

    static readonly Regex TdRe = new(
        @"(<td\b[^>]*>)([\s\S]*?)(</td>)",
        RegexOptions.IgnoreCase | RegexOptions.CultureInvariant | RegexOptions.Compiled);

    static bool IsRawHtmlToken(string key) =>
        key.Equals("Hinh_Anh", StringComparison.Ordinal);

    static string EncodeToken(string key, string value) =>
        IsRawHtmlToken(key) ? value : WebUtility.HtmlEncode(value);

    public static string Render(
        string templateHtml,
        IReadOnlyDictionary<string, string> data,
        IReadOnlyList<IReadOnlyDictionary<string, string>> lineItems)
    {
        var html = EnsureItemLoop(templateHtml ?? "");
        var begin = html.IndexOf(ItemBegin, StringComparison.Ordinal);
        var end = html.IndexOf(ItemEnd, StringComparison.Ordinal);
        if (begin >= 0 && end > begin)
        {
            var block = html[(begin + ItemBegin.Length)..end];
            var sb = new StringBuilder();
            foreach (var row in lineItems)
            {
                var line = block;
                foreach (var (k, v) in row)
                    line = line.Replace("{" + k + "}", EncodeToken(k, v), StringComparison.Ordinal);
                sb.Append(line);
            }
            html = html[..begin] + sb + html[(end + ItemEnd.Length)..];
        }

        foreach (var (k, v) in data)
            html = html.Replace("{" + k + "}", WebUtility.HtmlEncode(v), StringComparison.Ordinal);

        if (!html.Contains("<html", StringComparison.OrdinalIgnoreCase))
        {
            var paper = data.TryGetValue("PaperSize", out var p) ? p : "A4";
            html =
                "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><style>" +
                "@page { size: " + paper + " portrait; margin: 12mm; }" +
                "body{font-family:Arial,sans-serif;font-size:13px;color:#222;max-width:210mm;margin:0 auto}" +
                "</style></head><body>" + html + "</body></html>";
        }
        return html;
    }

    /// <summary>
    /// contenteditable / Word import hay mất &lt;!--BEGIN_ITEMS--&gt; hoặc để sẵn 1 dòng Aquafina.
    /// Gắn lại vòng hàng trước khi bind dữ liệu thật.
    /// </summary>
    public static string EnsureItemLoop(string html)
    {
        if (string.IsNullOrEmpty(html)) return html;
        if (html.Contains(ItemBegin, StringComparison.Ordinal) &&
            html.Contains(ItemEnd, StringComparison.Ordinal) &&
            ItemLoopIsUsable(html))
            return html;

        html = html.Replace(ItemBegin, "", StringComparison.Ordinal)
            .Replace(ItemEnd, "", StringComparison.Ordinal);

        var tokenAt = html.IndexOf("{Ten_Hang_Hoa}", StringComparison.Ordinal);
        if (tokenAt >= 0)
        {
            var trStart = LastIndexOfIgnoreCase(html, "<tr", tokenAt);
            var trEnd = html.IndexOf("</tr>", tokenAt, StringComparison.OrdinalIgnoreCase);
            if (trStart >= 0 && trEnd > trStart)
            {
                var after = trEnd + 5;
                return html[..trStart] + ItemBegin + html[trStart..after] + ItemEnd + html[after..];
            }
        }

        foreach (Match table in TableRe.Matches(html))
        {
            if (!LooksLikeProductTable(table.Value)) continue;
            var tbody = TbodyRe.Match(table.Value);
            if (!tbody.Success) continue;
            var inner = tbody.Groups[2].Value;
            if (inner.Contains("{Tong_Cong}", StringComparison.Ordinal)) continue;
            string? dataRow = null;
            foreach (Match row in TrRe.Matches(inner))
            {
                if (row.Value.Contains("<th", StringComparison.OrdinalIgnoreCase)) continue;
                dataRow = row.Value;
                break;
            }
            if (dataRow == null) continue;
            var tokenRow = TokenizeProductRow(dataRow);
            var newTable = table.Value.Remove(tbody.Index, tbody.Length)
                .Insert(tbody.Index, tbody.Groups[1].Value + ItemBegin + tokenRow + ItemEnd + tbody.Groups[3].Value);
            return html[..table.Index] + newTable + html[(table.Index + table.Length)..];
        }

        var close = LastIndexOfIgnoreCase(html, "</div>", html.Length);
        if (close >= 0)
            return html[..close] + DefaultItemTable + html[close..];
        return html + DefaultItemTable;
    }

    static bool ItemLoopIsUsable(string html)
    {
        var begin = html.IndexOf(ItemBegin, StringComparison.Ordinal);
        var end = html.IndexOf(ItemEnd, StringComparison.Ordinal);
        if (begin < 0 || end <= begin) return false;
        var block = html[(begin + ItemBegin.Length)..end];
        return block.Contains("{Ten_Hang_Hoa}", StringComparison.Ordinal) &&
               (block.Contains("<tr", StringComparison.OrdinalIgnoreCase) ||
                block.Contains("<td", StringComparison.OrdinalIgnoreCase));
    }

    static bool LooksLikeProductTable(string tableHtml)
    {
        var t = tableHtml.ToLowerInvariant();
        if (t.Contains("{ten_hang_hoa}") || t.Contains("begin_items")) return true;
        if (t.Contains("tên hàng") || t.Contains("ten hang") || t.Contains("hàng hóa") ||
            t.Contains("thành tiền") || t.Contains("thanh tien") || t.Contains("đơn giá") ||
            t.Contains("don gia"))
            return true;
        if (Regex.IsMatch(t, @">\s*stt\s*<")) return true;
        var firstTr = TrRe.Match(tableHtml);
        return firstTr.Success && TdRe.Matches(firstTr.Value).Count >= 4;
    }

    static string TokenizeProductRow(string tr)
    {
        var tds = TdRe.Matches(tr);
        if (tds.Count == 0) return tr;
        string[] tokens = tds.Count switch
        {
            4 => ["Ten_Hang_Hoa", "So_Luong", "Don_Gia", "Thanh_Tien"],
            5 => ["STT", "Ten_Hang_Hoa", "So_Luong", "Don_Gia", "Thanh_Tien"],
            6 => ["STT", "Ten_Hang_Hoa", "Don_Vi_Tinh", "So_Luong", "Don_Gia", "Thanh_Tien"],
            _ => ["STT", "Ten_Hang_Hoa", "Don_Vi_Tinh", "So_Luong", "Don_Gia", "Thanh_Tien", "Bao_Hanh"],
        };
        var i = 0;
        return TdRe.Replace(tr, m =>
        {
            var tok = i < tokens.Length ? tokens[i] : "Ghi_Chu";
            i++;
            return m.Groups[1].Value + "{" + tok + "}" + m.Groups[3].Value;
        });
    }

    static int LastIndexOfIgnoreCase(string haystack, string needle, int startIndex)
    {
        if (startIndex > haystack.Length) startIndex = haystack.Length;
        if (startIndex <= 0) return -1;
        return haystack.LastIndexOf(needle, startIndex - 1, StringComparison.OrdinalIgnoreCase);
    }
}

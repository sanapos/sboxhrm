using System.Net;
using System.Text;

namespace ZKTecoADMS.Api.Services;

/// <summary>Ghép {Token} + &lt;!--BEGIN_ITEMS--&gt; giống Flutter renderPosPrintTemplateHtml.</summary>
public static class PosPrintTemplateHtmlRenderer
{
    const string ItemBegin = "<!--BEGIN_ITEMS-->";
    const string ItemEnd = "<!--END_ITEMS-->";

    static bool IsRawHtmlToken(string key) =>
        key.Equals("Hinh_Anh", StringComparison.Ordinal);

    static string EncodeToken(string key, string value) =>
        IsRawHtmlToken(key) ? value : WebUtility.HtmlEncode(value);

    public static string Render(
        string templateHtml,
        IReadOnlyDictionary<string, string> data,
        IReadOnlyList<IReadOnlyDictionary<string, string>> lineItems)
    {
        var html = templateHtml ?? "";
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
}

using System.IO.Compression;
using System.Text;
using System.Text.RegularExpressions;
using System.Xml.Linq;

namespace ZKTecoADMS.Api.Services;

/// <summary>Một đoạn văn trong file Word: Id = "{part}:{chỉ số}" (part: document / header1 / footer2...).</summary>
public sealed record DocxParagraph(string Id, string Text, bool InTable);

/// <summary>Thay cụm chữ <see cref="Find"/> trong đoạn <see cref="ParagraphId"/> bằng mã trường {Field}.</summary>
public sealed record DocxReplacement(string ParagraphId, string Find, string Field);

/// <summary>
/// Mẫu Word giữ nguyên bố cục: chèn mã trường {Field} vào đúng đoạn văn (giữ run / định dạng),
/// rồi điền dữ liệu; dòng bảng chứa trường của hàng hóa ({STT}, {Ten_Hang_Hoa}...) được nhân bản theo số dòng.
/// </summary>
public static class DocxTemplateEngine
{
    static readonly XNamespace W = "http://schemas.openxmlformats.org/wordprocessingml/2006/main";
    static readonly XNamespace Xml = XNamespace.Xml;
    static readonly Regex TokenRx = new(@"\{([A-Za-z][A-Za-z0-9_]*)\}", RegexOptions.Compiled);
    static readonly Regex PartRx = new(@"^word/(document|header\d*|footer\d*)\.xml$", RegexOptions.Compiled);

    /// <summary>Trường chỉ có ở dòng hàng — có trong w:tr thì dòng đó là dòng hàng mẫu.</summary>
    static readonly HashSet<string> ItemRowKeys =
    [
        "STT", "Ma_Hang", "Ten_Hang_Hoa", "Don_Vi_Tinh", "So_Luong", "Don_Gia",
        "Chiet_Khau", "Thanh_Tien", "Chieu_Dai", "Chieu_Rong", "Chieu_Cao", "Hinh_Anh",
    ];

    // ─── Đọc ────────────────────────────────────────────────────────────

    public static List<DocxParagraph> ExtractParagraphs(byte[] docx)
    {
        var result = new List<DocxParagraph>();
        ForEachPart(docx, readOnly: true, (partName, doc) =>
        {
            var i = 0;
            foreach (var p in doc.Descendants(W + "p"))
            {
                var id = $"{partName}:{i++}";
                var text = ParagraphText(p);
                if (text.Trim().Length == 0) continue;
                result.Add(new DocxParagraph(id, text, p.Ancestors(W + "tc").Any()));
            }
        });
        return result;
    }

    // ─── Chèn mã trường vào mẫu ────────────────────────────────────────

    /// <summary>
    /// Áp các thay thế (cụm chữ phải có thật trong đoạn) + xóa các dòng bảng mẫu thừa.
    /// Trả file mới và danh sách thay thế đã áp được.
    /// </summary>
    public static (byte[] Docx, List<DocxReplacement> Applied) ApplyReplacements(
        byte[] docx, IReadOnlyList<DocxReplacement> replacements, IReadOnlyCollection<string>? removeRowParagraphIds = null)
    {
        var applied = new List<DocxReplacement>();
        var removeIds = new HashSet<string>(removeRowParagraphIds ?? []);
        var bytes = ForEachPart(docx, readOnly: false, (partName, doc) =>
        {
            var paragraphs = doc.Descendants(W + "p").ToList();
            var rowsToRemove = new HashSet<XElement>();
            for (var i = 0; i < paragraphs.Count; i++)
            {
                var id = $"{partName}:{i}";
                foreach (var r in replacements.Where(r => r.ParagraphId == id))
                {
                    if (ReplaceInParagraph(paragraphs[i], r.Find, "{" + r.Field + "}"))
                        applied.Add(r);
                }
                if (removeIds.Contains(id) && paragraphs[i].Ancestors(W + "tr").FirstOrDefault() is { } tr)
                    rowsToRemove.Add(tr);
            }
            foreach (var tr in rowsToRemove)
            {
                // Không xóa dòng đã được gắn mã trường (dòng hàng mẫu giữ lại).
                if (!TokenRx.IsMatch(string.Concat(tr.Descendants(W + "t").Select(t => t.Value))))
                    tr.Remove();
            }
        });
        return (bytes, applied);
    }

    // ─── Điền dữ liệu ──────────────────────────────────────────────────

    /// <summary>
    /// Điền <paramref name="data"/> vào mẫu; dòng bảng chứa trường của <paramref name="lines"/>
    /// được nhân bản cho từng dòng hàng. Giá trị HTML (ảnh, con dấu) bị bỏ qua.
    /// </summary>
    public static byte[] Render(
        byte[] template,
        IReadOnlyDictionary<string, string> data,
        IReadOnlyList<IReadOnlyDictionary<string, string>> lines)
    {
        return ForEachPart(template, readOnly: false, (_, doc) =>
        {
            foreach (var p in doc.Descendants(W + "p").ToList())
                NormalizeTokens(p);

            // Dòng hàng: w:tr (không lồng) có trường riêng của dòng hàng. Không dùng Ghi_Chu / Bao_Hanh
            // để nhận diện — hai trường này cũng là trường chung (bảng bố cục sẽ bị nhân bản nhầm).
            var itemRows = doc.Descendants(W + "tr")
                .Where(tr => TokensIn(tr).Any(ItemRowKeys.Contains))
                .Where(tr => !tr.Ancestors(W + "tr").Any())
                .ToList();
            foreach (var tr in itemRows)
            {
                var anchor = tr;
                foreach (var line in lines)
                {
                    var clone = new XElement(tr);
                    FillTokens(clone, key => line.TryGetValue(key, out var v) ? v : data.GetValueOrDefault(key));
                    anchor.AddAfterSelf(clone);
                    anchor = clone;
                }
                tr.Remove();
            }

            FillTokens(doc.Root!, key => data.GetValueOrDefault(key));
        });
    }

    // ─── Nội bộ ─────────────────────────────────────────────────────────

    static byte[] ForEachPart(byte[] docx, bool readOnly, Action<string, XDocument> action)
    {
        using var input = new MemoryStream(docx);
        using var output = new MemoryStream();
        using (var src = new ZipArchive(input, ZipArchiveMode.Read))
        using (var dst = readOnly ? null : new ZipArchive(output, ZipArchiveMode.Create, leaveOpen: true))
        {
            if (src.GetEntry("word/document.xml") == null)
                throw new InvalidOperationException("File Word không hợp lệ (thiếu word/document.xml). Lưu lại dạng .docx rồi thử.");
            foreach (var entry in src.Entries)
            {
                var m = PartRx.Match(entry.FullName);
                if (!m.Success)
                {
                    if (dst == null) continue;
                    var copy = dst.CreateEntry(entry.FullName, CompressionLevel.Optimal);
                    using var from = entry.Open();
                    using var to = copy.Open();
                    from.CopyTo(to);
                    continue;
                }
                XDocument doc;
                using (var s = entry.Open()) doc = XDocument.Load(s, LoadOptions.PreserveWhitespace);
                action(m.Groups[1].Value, doc);
                if (dst == null) continue;
                var outEntry = dst.CreateEntry(entry.FullName, CompressionLevel.Optimal);
                using var os = outEntry.Open();
                doc.Save(os, SaveOptions.DisableFormatting);
            }
        }
        return readOnly ? docx : output.ToArray();
    }

    /// <summary>w:t thuộc trực tiếp đoạn (không tính đoạn lồng trong textbox).</summary>
    static List<XElement> TextNodes(XElement p) =>
        p.Descendants(W + "t").Where(t => t.Ancestors(W + "p").First() == p).ToList();

    static string ParagraphText(XElement p) => string.Concat(TextNodes(p).Select(t => t.Value));

    static IEnumerable<string> TokensIn(XElement e) =>
        TokenRx.Matches(string.Concat(e.Descendants(W + "t").Select(t => t.Value))).Select(m => m.Groups[1].Value);

    /// <summary>Thay lần xuất hiện đầu của <paramref name="find"/> (có thể trải nhiều run) — giữ định dạng run đầu.</summary>
    static bool ReplaceInParagraph(XElement p, string find, string replacement)
    {
        if (string.IsNullOrEmpty(find)) return false;
        var nodes = TextNodes(p);
        var full = string.Concat(nodes.Select(n => n.Value));
        var start = full.IndexOf(find, StringComparison.Ordinal);
        if (start < 0) return false;
        var end = start + find.Length;

        var pos = 0;
        var placed = false;
        foreach (var n in nodes)
        {
            var nStart = pos;
            var nEnd = pos + n.Value.Length;
            pos = nEnd;
            if (nEnd <= start || nStart >= end) continue;
            var cutFrom = Math.Max(start, nStart) - nStart;
            var cutTo = Math.Min(end, nEnd) - nStart;
            var before = n.Value[..cutFrom];
            var after = n.Value[cutTo..];
            n.Value = placed ? before + after : before + replacement + after;
            placed = true;
            n.SetAttributeValue(Xml + "space", "preserve");
        }
        return placed;
    }

    /// <summary>Gom mã {Field} bị Word tách qua nhiều run về một run (sửa mẫu tay trong Word hay gặp).</summary>
    static void NormalizeTokens(XElement p)
    {
        var nodes = TextNodes(p);
        if (nodes.Count < 2) return;
        var full = string.Concat(nodes.Select(n => n.Value));
        foreach (Match m in TokenRx.Matches(full))
        {
            if (nodes.Any(n => n.Value.Contains(m.Value, StringComparison.Ordinal))) continue;
            ReplaceInParagraph(p, m.Value, m.Value);
        }
    }

    static void FillTokens(XElement root, Func<string, string?> lookup)
    {
        foreach (var t in root.Descendants(W + "t").ToList())
        {
            if (!t.Value.Contains('{')) continue;
            var replaced = TokenRx.Replace(t.Value, m =>
            {
                var v = lookup(m.Groups[1].Value);
                if (v == null) return m.Value; // trường lạ: để nguyên để người dùng thấy
                return LooksLikeHtml(v) ? "" : v;
            });
            if (replaced == t.Value) continue;
            t.SetAttributeValue(Xml + "space", "preserve");
            SetTextWithBreaks(t, replaced);
        }
    }

    static bool LooksLikeHtml(string v)
    {
        var s = v.TrimStart();
        return s.StartsWith("<img", StringComparison.OrdinalIgnoreCase)
            || s.StartsWith("<div", StringComparison.OrdinalIgnoreCase);
    }

    /// <summary>Giá trị nhiều dòng → w:t + w:br trong cùng run.</summary>
    static void SetTextWithBreaks(XElement t, string value)
    {
        var parts = value.Replace("\r\n", "\n").Split('\n');
        t.Value = parts[0];
        var after = t;
        for (var i = 1; i < parts.Length; i++)
        {
            var br = new XElement(W + "br");
            var nt = new XElement(W + "t", new XAttribute(Xml + "space", "preserve"), parts[i]);
            after.AddAfterSelf(br, nt);
            after = nt;
        }
    }

    /// <summary>Văn bản thuần của mẫu (xem trước / danh sách mẫu).</summary>
    public static string ToPlainHtml(byte[] docx)
    {
        var sb = new StringBuilder("<!--DOCX_TEMPLATE--><div style=\"font-family:'Times New Roman',serif;font-size:13px\">");
        foreach (var p in ExtractParagraphs(docx))
            sb.Append("<p style=\"margin:0 0 6px\">").Append(System.Net.WebUtility.HtmlEncode(p.Text)).Append("</p>");
        return sb.Append("</div>").ToString();
    }
}

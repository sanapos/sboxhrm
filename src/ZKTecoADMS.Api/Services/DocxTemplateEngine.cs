using System.IO.Compression;
using System.Text;
using System.Text.RegularExpressions;
using System.Xml.Linq;

namespace ZKTecoADMS.Api.Services;

/// <summary>Một đoạn văn trong file Word: Id = "{part}:{chỉ số}" (part: document / header1 / footer2...).</summary>
public sealed record DocxParagraph(string Id, string Text, bool InTable);

/// <summary>
/// Thay cụm chữ <see cref="Find"/> trong đoạn <see cref="ParagraphId"/> bằng mã trường {Field}.
/// <see cref="Start"/> = vị trí ký tự trong đoạn GỐC (chọn trên màn soạn — đúng lần xuất hiện);
/// null = lần xuất hiện đầu chưa bị thay (AI / dữ liệu cũ).
/// Field <c>_Text</c> = sửa câu chữ cố định thành <see cref="Text"/>; <c>_Xoa</c> = xóa cụm chữ.
/// </summary>
public sealed record DocxReplacement(string ParagraphId, string Find, string Field, int? Start = null, string? Text = null);

/// <summary>
/// Mẫu Word giữ nguyên bố cục: chèn mã trường {Field} vào đúng đoạn văn (giữ run / định dạng),
/// rồi điền dữ liệu; dòng bảng chứa trường của hàng hóa ({STT}, {Ten_Hang_Hoa}...) được nhân bản theo số dòng.
/// </summary>
public static class DocxTemplateEngine
{
    static readonly XNamespace W = "http://schemas.openxmlformats.org/wordprocessingml/2006/main";
    static readonly XNamespace Xml = XNamespace.Xml;
    static readonly Regex TokenRx = new(@"\{([A-Za-z][A-Za-z0-9_]*)\}", RegexOptions.Compiled);
    /// <summary>Trường đặc biệt: xóa cụm chữ (phần thừa của giá trị bị ngắt dòng).</summary>
    public const string ClearField = "_Xoa";
    /// <summary>Trường đặc biệt: sửa câu chữ cố định (giá trị trong DocxReplacement.Text).</summary>
    public const string TextField = "_Text";

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
                var mine = replacements.Where(r => r.ParagraphId == id).ToList();
                if (mine.Count > 0)
                {
                    // Xác định vị trí trên chữ GỐC rồi thay từ cuối lên đầu (vị trí phía trước không bị lệch).
                    var resolved = ResolveRanges(ParagraphText(paragraphs[i]), mine);
                    foreach (var r in resolved.OrderByDescending(x => x.Start).ThenBy(x => x.Find.Length == 0 ? 0 : 1))
                    {
                        if (r.Find.Length == 0) InsertAt(paragraphs[i], r.Start!.Value, ValueOf(r));
                        else ReplaceAt(paragraphs[i], r.Start!.Value, r.Find.Length, ValueOf(r));
                    }
                    applied.AddRange(resolved);
                }
                if (removeIds.Contains(id) && paragraphs[i].Ancestors(W + "tr").FirstOrDefault() is { } tr)
                    rowsToRemove.Add(tr);
            }
            // Dòng hàng mẫu: ô không gắn trường là dữ liệu mẫu cũ → để trống (không lặp theo mọi dòng).
            foreach (var tr in doc.Descendants(W + "tr")
                         .Where(tr => TokensIn(tr).Any(ItemRowKeys.Contains) && !tr.Ancestors(W + "tr").Any()))
            {
                foreach (var tc in tr.Elements(W + "tc"))
                {
                    var cellText = string.Concat(tc.Descendants(W + "t").Select(t => t.Value));
                    if (cellText.Trim().Length == 0 || TokenRx.IsMatch(cellText)) continue;
                    foreach (var t in tc.Descendants(W + "t")) t.Value = "";
                }
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
        var media = new List<DocxImage>();
        var filled = ForEachPart(template, readOnly: false, (partName, doc) =>
        {
            ImageSink sink = (bytes, ext) =>
            {
                var n = media.Count + 1;
                var img = new DocxImage(partName, $"rIdSbox{n}", $"media/sbox_{n}.{ext}", bytes, ext, 100000 + n);
                media.Add(img);
                return img;
            };
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
                    FillTokens(clone, key => line.TryGetValue(key, out var v) ? v : data.GetValueOrDefault(key), sink);
                    anchor.AddAfterSelf(clone);
                    anchor = clone;
                }
                tr.Remove();
            }

            FillTokens(doc.Root!, key => data.GetValueOrDefault(key), sink);
        });
        return media.Count == 0 ? filled : AddMedia(filled, media);
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

    static string ValueOf(DocxReplacement r) => r.Field switch
    {
        ClearField => "",
        TextField => r.Text ?? "",
        _ => "{" + r.Field + "}",
    };

    /// <summary>
    /// Vị trí từng thay thế trong chữ gốc của đoạn: dùng <c>Start</c> nếu đúng chữ ở đó, không thì lần xuất hiện
    /// đầu tiên chưa bị thay thế khác chiếm. Các vùng không chồng lên nhau. Trả bản ghi có Start đã xác định.
    /// </summary>
    public static List<DocxReplacement> ResolveRanges(string text, IEnumerable<DocxReplacement> replacements)
    {
        var taken = new List<(int S, int E)>();
        var result = new List<DocxReplacement>();
        bool Free(int s, int len) => taken.All(t => s + len <= t.S || s >= t.E);
        foreach (var r in replacements)
        {
            // Chèn trường vào vị trí (ô trống / cuối đoạn): Find rỗng + Start.
            if (string.IsNullOrEmpty(r.Find))
            {
                if (r.Start is int at && at >= 0 && at <= text.Length && taken.All(t => at <= t.S || at >= t.E))
                    result.Add(r with { Find = "", Start = at });
                continue;
            }
            var len = r.Find.Length;
            var start = -1;
            if (r.Start is int s && s >= 0 && s + len <= text.Length
                && string.CompareOrdinal(text, s, r.Find, 0, len) == 0 && Free(s, len))
                start = s;
            else
            {
                var idx = text.IndexOf(r.Find, StringComparison.Ordinal);
                while (idx >= 0 && !Free(idx, len))
                    idx = text.IndexOf(r.Find, idx + 1, StringComparison.Ordinal);
                start = idx;
            }
            if (start < 0) continue;
            taken.Add((start, start + len));
            result.Add(r with { Start = start });
        }
        return result;
    }

    /// <summary>Thay lần xuất hiện đầu của <paramref name="find"/> (có thể trải nhiều run) — giữ định dạng run đầu.</summary>
    static bool ReplaceInParagraph(XElement p, string find, string replacement)
    {
        if (string.IsNullOrEmpty(find)) return false;
        var full = ParagraphText(p);
        var start = full.IndexOf(find, StringComparison.Ordinal);
        if (start < 0) return false;
        return ReplaceAt(p, start, find.Length, replacement);
    }

    /// <summary>
    /// Chèn chữ / mã trường tại vị trí <paramref name="offset"/> của đoạn. Đoạn trống (ô bảng trống) → tạo run mới
    /// theo định dạng dấu đoạn (w:pPr/w:rPr) để giữ font / cỡ chữ của ô.
    /// </summary>
    static void InsertAt(XElement p, int offset, string value)
    {
        var nodes = TextNodes(p);
        var pos = 0;
        foreach (var n in nodes)
        {
            if (offset >= pos && offset <= pos + n.Value.Length)
            {
                n.Value = n.Value[..(offset - pos)] + value + n.Value[(offset - pos)..];
                n.SetAttributeValue(Xml + "space", "preserve");
                return;
            }
            pos += n.Value.Length;
        }
        var markProps = p.Element(W + "pPr")?.Element(W + "rPr");
        var rPr = markProps == null ? null : new XElement(W + "rPr", markProps.Elements()
            .Where(e => e.Name.LocalName is not ("ins" or "del" or "moveFrom" or "moveTo" or "rPrChange"))
            .Select(e => new XElement(e)));
        p.Add(new XElement(W + "r", rPr, new XElement(W + "t", new XAttribute(Xml + "space", "preserve"), value)));
    }

    /// <summary>Thay đoạn chữ [start, start+length) của đoạn văn (có thể trải nhiều run) — giữ định dạng run đầu.</summary>
    static bool ReplaceAt(XElement p, int start, int length, string replacement)
    {
        var nodes = TextNodes(p);
        var end = start + length;

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

    static void FillTokens(XElement root, Func<string, string?> lookup, ImageSink? images = null)
    {
        foreach (var t in root.Descendants(W + "t").ToList())
        {
            if (!t.Value.Contains('{')) continue;
            if (images != null && TryFillWithImages(t, lookup, images)) continue;
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

    // ─── Ảnh động (logo, con dấu, ảnh sản phẩm) ───────────────────────

    /// <summary>Ảnh chèn vào một phần (document / header…): quan hệ rId + tệp media.</summary>
    sealed record DocxImage(string Part, string RelId, string Target, byte[] Bytes, string Ext, int DocPrId);

    delegate DocxImage ImageSink(byte[] bytes, string ext);

    static readonly Regex DataImageRx = new(
        @"src\s*=\s*[""']data:image/(png|jpe?g|gif);base64,([A-Za-z0-9+/=\s]+)[""']",
        RegexOptions.Compiled | RegexOptions.IgnoreCase);

    /// <summary>Trường ảnh — gắn được ở màn soạn; giá trị là ảnh nhúng (data:).</summary>
    public static readonly HashSet<string> ImageKeys = ["Logo", "Con_Dau", "Chu_Ky", "Hinh_Anh"];

    /// <summary>Khung tối đa (mm) theo trường ảnh — giữ tỉ lệ ảnh gốc.</summary>
    static (double W, double H) ImageBox(string key) => key switch
    {
        "Logo" => (40, 22),
        "Con_Dau" => (38, 38),
        "Chu_Ky" => (40, 20),
        "Hinh_Anh" => (22, 22),
        _ => (30, 30),
    };

    /// <summary>Ảnh nhúng dạng data: (không tải URL ngoài) → bytes + phần mở rộng.</summary>
    static (byte[] Bytes, string Ext)? ParseDataImage(string? html)
    {
        if (string.IsNullOrEmpty(html)) return null;
        var m = DataImageRx.Match(html);
        if (!m.Success) return null;
        try
        {
            var bytes = Convert.FromBase64String(Regex.Replace(m.Groups[2].Value, @"\s", ""));
            if (bytes.Length < 16 || bytes.Length > 8_000_000) return null;
            var ext = m.Groups[1].Value.ToLowerInvariant() switch { "jpg" or "jpeg" => "jpeg", var e => e };
            return (bytes, ext);
        }
        catch (FormatException)
        {
            return null;
        }
    }

    /// <summary>Mẩu chữ có mã trường ảnh mang ảnh thật → tách run: chữ / ảnh / chữ. Trả false nếu không có ảnh.</summary>
    static bool TryFillWithImages(XElement t, Func<string, string?> lookup, ImageSink images)
    {
        var run = t.Parent;
        if (run == null || run.Name != W + "r" || run.Parent == null) return false;
        var found = TokenRx.Matches(t.Value).Select(m => (m, img: ParseDataImage(lookup(m.Groups[1].Value)))).ToList();
        if (found.All(f => f.img == null)) return false;

        var rPr = run.Element(W + "rPr");
        var pieces = new List<XElement>();
        var last = 0;
        string Text(string raw) => TokenRx.Replace(raw, m =>
        {
            var v = lookup(m.Groups[1].Value);
            return v == null ? m.Value : LooksLikeHtml(v) ? "" : v;
        });
        foreach (var (m, img) in found)
        {
            if (img == null) continue;
            if (m.Index > last) pieces.Add(TextRun(rPr, Text(t.Value[last..m.Index])));
            pieces.Add(DrawingRun(images(img.Value.Bytes, img.Value.Ext), ImageBox(m.Groups[1].Value)));
            last = m.Index + m.Length;
        }
        if (last < t.Value.Length) pieces.Add(TextRun(rPr, Text(t.Value[last..])));

        var before = t.ElementsBeforeSelf().Where(e => e.Name != W + "rPr").ToList();
        var after = t.ElementsAfterSelf().ToList();
        if (before.Count > 0)
            run.AddBeforeSelf(new XElement(W + "r", rPr == null ? null : new XElement(rPr), before.Select(e => new XElement(e))));
        XElement anchor = run;
        foreach (var piece in pieces)
        {
            anchor.AddAfterSelf(piece);
            anchor = piece;
        }
        if (after.Count > 0)
            anchor.AddAfterSelf(new XElement(W + "r", rPr == null ? null : new XElement(rPr), after.Select(e => new XElement(e))));
        run.Remove();
        return true;
    }

    static XElement TextRun(XElement? rPr, string text)
    {
        var t = new XElement(W + "t", new XAttribute(Xml + "space", "preserve"));
        var r = new XElement(W + "r", rPr == null ? null : new XElement(rPr), t);
        SetTextWithBreaks(t, text);
        return r;
    }

    static readonly XNamespace Wp = "http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing";
    static readonly XNamespace A = "http://schemas.openxmlformats.org/drawingml/2006/main";
    static readonly XNamespace Pic = "http://schemas.openxmlformats.org/drawingml/2006/picture";
    static readonly XNamespace RelNs = "http://schemas.openxmlformats.org/officeDocument/2006/relationships";

    static XElement DrawingRun(DocxImage img, (double W, double H) boxMm)
    {
        // Kích thước giữ tỉ lệ ảnh, vừa khung (mm → EMU: 36000).
        double pw = 1, ph = 1;
        try
        {
            var info = SixLabors.ImageSharp.Image.Identify(img.Bytes);
            pw = Math.Max(1, info.Width);
            ph = Math.Max(1, info.Height);
        }
        catch (Exception)
        {
            // Không đọc được kích thước → vuông.
        }
        var scale = Math.Min(boxMm.W / pw, boxMm.H / ph);
        var cx = (long)(pw * scale * 36000);
        var cy = (long)(ph * scale * 36000);
        var name = "Sbox image " + img.DocPrId;
        return new XElement(W + "r",
            new XElement(W + "drawing",
                new XElement(Wp + "inline",
                    new XAttribute("distT", 0), new XAttribute("distB", 0), new XAttribute("distL", 0), new XAttribute("distR", 0),
                    new XElement(Wp + "extent", new XAttribute("cx", cx), new XAttribute("cy", cy)),
                    new XElement(Wp + "docPr", new XAttribute("id", img.DocPrId), new XAttribute("name", name)),
                    new XElement(A + "graphic",
                        new XElement(A + "graphicData", new XAttribute("uri", Pic.NamespaceName),
                            new XElement(Pic + "pic",
                                new XElement(Pic + "nvPicPr",
                                    new XElement(Pic + "cNvPr", new XAttribute("id", img.DocPrId), new XAttribute("name", name)),
                                    new XElement(Pic + "cNvPicPr")),
                                new XElement(Pic + "blipFill",
                                    new XElement(A + "blip", new XAttribute(RelNs + "embed", img.RelId)),
                                    new XElement(A + "stretch", new XElement(A + "fillRect"))),
                                new XElement(Pic + "spPr",
                                    new XElement(A + "xfrm",
                                        new XElement(A + "off", new XAttribute("x", 0), new XAttribute("y", 0)),
                                        new XElement(A + "ext", new XAttribute("cx", cx), new XAttribute("cy", cy))),
                                    new XElement(A + "prstGeom", new XAttribute("prst", "rect"), new XElement(A + "avLst")))))))));
    }

    /// <summary>Thêm tệp ảnh + quan hệ (rels) của từng phần + kiểu nội dung vào gói docx.</summary>
    static byte[] AddMedia(byte[] docx, List<DocxImage> media)
    {
        XNamespace pr = "http://schemas.openxmlformats.org/package/2006/relationships";
        XNamespace ct = "http://schemas.openxmlformats.org/package/2006/content-types";
        const string imageRel = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/image";
        using var input = new MemoryStream(docx);
        using var output = new MemoryStream();
        using (var src = new ZipArchive(input, ZipArchiveMode.Read))
        using (var dst = new ZipArchive(output, ZipArchiveMode.Create, leaveOpen: true))
        {
            var byRels = media.GroupBy(m => $"word/_rels/{m.Part}.xml.rels").ToDictionary(g => g.Key, g => g.ToList());
            void WriteXml(string name, XDocument doc)
            {
                using var os = dst.CreateEntry(name, CompressionLevel.Optimal).Open();
                doc.Save(os, SaveOptions.DisableFormatting);
            }
            foreach (var entry in src.Entries)
            {
                if (entry.FullName == "[Content_Types].xml")
                {
                    XDocument doc;
                    using (var s = entry.Open()) doc = XDocument.Load(s);
                    foreach (var ext in media.Select(m => m.Ext).Distinct())
                    {
                        if (doc.Root!.Elements(ct + "Default").Any(d => string.Equals((string?)d.Attribute("Extension"), ext, StringComparison.OrdinalIgnoreCase)))
                            continue;
                        doc.Root.AddFirst(new XElement(ct + "Default", new XAttribute("Extension", ext), new XAttribute("ContentType", "image/" + ext)));
                    }
                    WriteXml(entry.FullName, doc);
                    continue;
                }
                if (byRels.TryGetValue(entry.FullName, out var imgs))
                {
                    XDocument doc;
                    using (var s = entry.Open()) doc = XDocument.Load(s);
                    foreach (var m in imgs)
                        doc.Root!.Add(new XElement(pr + "Relationship", new XAttribute("Id", m.RelId),
                            new XAttribute("Type", imageRel), new XAttribute("Target", m.Target)));
                    WriteXml(entry.FullName, doc);
                    byRels.Remove(entry.FullName);
                    continue;
                }
                using var from = entry.Open();
                using var to = dst.CreateEntry(entry.FullName, CompressionLevel.Optimal).Open();
                from.CopyTo(to);
            }
            // Phần chưa có tệp rels (header / footer đơn giản) → tạo mới.
            foreach (var (name, imgs) in byRels)
                WriteXml(name, new XDocument(new XElement(pr + "Relationships",
                    imgs.Select(m => new XElement(pr + "Relationship", new XAttribute("Id", m.RelId),
                        new XAttribute("Type", imageRel), new XAttribute("Target", m.Target))))));
            foreach (var m in media)
            {
                using var os = dst.CreateEntry("word/" + m.Target, CompressionLevel.NoCompression).Open();
                os.Write(m.Bytes);
            }
        }
        return output.ToArray();
    }

    // ─── Bản xem "mẫu gắn trường" ───────────────────────────────────────

    /// <summary>
    /// Bản sao mẫu để xem: mỗi mã {Field} hiện thành «[Nhãn trường]» tô vàng (dòng hàng tô xanh),
    /// giữ nguyên định dạng chữ xung quanh. Chỉ để xem trước — không dùng để điền dữ liệu.
    /// </summary>
    public static byte[] HighlightFields(byte[] template, IReadOnlyDictionary<string, string> labels)
    {
        return ForEachPart(template, readOnly: false, (_, doc) =>
        {
            foreach (var p in doc.Descendants(W + "p").ToList())
                NormalizeTokens(p);
            // Tìm lại sau mỗi lần tách: một run có thể chứa nhiều w:t mang mã (bản sao phía sau cần xử lý tiếp).
            var skipped = new HashSet<XElement>();
            while (doc.Descendants(W + "t").FirstOrDefault(x => !skipped.Contains(x) && TokenRx.IsMatch(x.Value)) is { } t)
            {
                var run = t.Parent;
                if (run == null || run.Name != W + "r" || run.Parent == null)
                {
                    skipped.Add(t);
                    continue;
                }
                var rPr = run.Element(W + "rPr");
                var pieces = new List<XElement>();
                var last = 0;
                foreach (Match m in TokenRx.Matches(t.Value))
                {
                    if (m.Index > last) pieces.Add(MakeRun(rPr, t.Value[last..m.Index], null));
                    var key = m.Groups[1].Value;
                    var label = labels.TryGetValue(key, out var l) ? ShortLabel(l) : key;
                    pieces.Add(MakeRun(rPr, $"[{label}]", ItemRowKeys.Contains(key) ? "cyan" : "yellow"));
                    last = m.Index + m.Length;
                }
                if (last < t.Value.Length) pieces.Add(MakeRun(rPr, t.Value[last..], null));

                // Run có nhiều phần tử (w:t + w:br / w:tab…): tách tại đúng w:t này.
                var siblingsAfter = t.ElementsAfterSelf().ToList();
                var siblingsBefore = t.ElementsBeforeSelf().Where(e => e.Name != W + "rPr").ToList();
                if (siblingsBefore.Count > 0)
                    run.AddBeforeSelf(new XElement(W + "r", rPr == null ? null : new XElement(rPr), siblingsBefore.Select(e => new XElement(e))));
                XElement anchor = run;
                foreach (var piece in pieces)
                {
                    anchor.AddAfterSelf(piece);
                    anchor = piece;
                }
                if (siblingsAfter.Count > 0)
                    anchor.AddAfterSelf(new XElement(W + "r", rPr == null ? null : new XElement(rPr), siblingsAfter.Select(e => new XElement(e))));
                run.Remove();
            }
        });
    }

    static string ShortLabel(string label)
    {
        // "Tên công ty / cửa hàng BÊN BÁN (bên B …)" → "Tên công ty / cửa hàng BÊN BÁN"
        var cut = label.IndexOf(" (", StringComparison.Ordinal);
        var s = cut > 0 ? label[..cut] : label;
        return s.Length > 40 ? s[..40] + "…" : s;
    }

    static XElement MakeRun(XElement? rPr, string text, string? highlight)
    {
        var props = rPr == null ? new XElement(W + "rPr") : new XElement(rPr);
        if (highlight != null)
        {
            props.Elements(W + "highlight").Remove();
            props.Elements(W + "shd").Remove();
            props.Add(new XElement(W + "highlight", new XAttribute(W + "val", highlight)));
        }
        return new XElement(W + "r", props,
            new XElement(W + "t", new XAttribute(Xml + "space", "preserve"), text));
    }

    /// <summary>Ảnh mẫu (khối màu) cho in thử trường ảnh — thấy đúng vị trí / cỡ ảnh.</summary>
    static string SampleImage(byte r, byte g, byte b, int w, int h)
    {
        using var img = new SixLabors.ImageSharp.Image<SixLabors.ImageSharp.PixelFormats.Rgba32>(
            w, h, new SixLabors.ImageSharp.PixelFormats.Rgba32(r, g, b, 90));
        using var ms = new MemoryStream();
        SixLabors.ImageSharp.ImageExtensions.SaveAsPng(img, ms);
        return "<img src=\"data:image/png;base64," + Convert.ToBase64String(ms.ToArray()) + "\"/>";
    }

    /// <summary>Dữ liệu mẫu để in thử (không cần chọn báo giá / hóa đơn thật).</summary>
    public static (Dictionary<string, string> Data, List<IReadOnlyDictionary<string, string>> Lines) SampleData()
    {
        var data = new Dictionary<string, string>
        {
            ["Ten_Cong_Ty"] = "CÔNG TY TNHH SBOX VIỆT NAM",
            ["Ten_Cua_Hang"] = "SBOX POS",
            ["Dia_Chi_Cong_Ty"] = "123 Nguyễn Văn Linh, Q.7, TP. Hồ Chí Minh",
            ["Dia_Chi_Chi_Nhanh"] = "123 Nguyễn Văn Linh, Q.7, TP. Hồ Chí Minh",
            ["Dien_Thoai_Cong_Ty"] = "0909 123 456",
            ["Email_Cua_Hang"] = "lienhe@sbox.vn",
            ["MST_Cong_Ty"] = "0312345678",
            ["Tai_Khoan_Cua_Hang"] = "0071 0001 23456",
            ["Ngan_Hang_Cua_Hang"] = "Vietcombank - CN Sài Gòn",
            ["Chu_Tai_Khoan_Cua_Hang"] = "CONG TY TNHH SBOX VIET NAM",
            ["Nguoi_Dai_Dien_Cua_Hang"] = "Nguyễn Văn Bình",
            ["Chuc_Vu_Cua_Hang"] = "Giám đốc",
            ["Ma_Bao_Gia"] = "BG-2026-0001",
            ["So_Hop_Dong"] = "HĐ-2026-0001",
            ["So_Chung_Tu"] = "CT-2026-0001",
            ["Ma_Hoa_Don"] = "HD000123",
            ["Ngay"] = DateTime.UtcNow.AddHours(7).ToString("dd/MM/yyyy"),
            ["Ngay_Hop_Dong"] = DateTime.UtcNow.AddHours(7).ToString("dd/MM/yyyy"),
            ["Khach_Hang"] = "Trần Thị Mai",
            ["Ten_Cong_Ty_Khach"] = "CÔNG TY CỔ PHẦN MINH AN",
            ["MST_Khach_Hang"] = "0109876543",
            ["Tai_Khoan_Khach_Hang"] = "1903 5555 6666 01",
            ["Ngan_Hang_Khach_Hang"] = "Techcombank",
            ["Nguoi_Dai_Dien_Khach"] = "Lê Minh An",
            ["Chuc_Vu_Khach"] = "Giám đốc",
            ["SDT"] = "0988 765 432",
            ["Dia_Chi_Khach_Hang"] = "45 Lê Lợi, Q.1, TP. Hồ Chí Minh",
            ["Dia_Diem_Thi_Cong"] = "45 Lê Lợi, Q.1, TP. Hồ Chí Minh",
            ["Han_Bao_Gia"] = DateTime.UtcNow.AddHours(7).AddDays(15).ToString("dd/MM/yyyy"),
            ["Tong_Tien_Hang"] = "23.000.000",
            ["Chiet_Khau_Hoa_Don"] = "500.000",
            ["Gia_Tri_Truoc_VAT"] = "22.500.000",
            ["Tien_Thue"] = "1.800.000",
            ["Tong_Cong"] = "24.300.000",
            ["Tong_Cong_Bang_Chu"] = "Hai mươi bốn triệu ba trăm nghìn đồng",
            ["Tien_Coc"] = "12.150.000",
            ["Tien_Coc_Bang_Chu"] = "Mười hai triệu một trăm năm mươi nghìn đồng",
            ["Phan_Tram_Coc"] = "50",
            ["Con_Lai_Hop_Dong"] = "12.150.000",
            ["Con_Lai_Bang_Chu"] = "Mười hai triệu một trăm năm mươi nghìn đồng",
            ["Hinh_Thuc_Thanh_Toan"] = "Chuyển khoản",
            ["Ky_Han_Thanh_Toan"] = "Trong 7 ngày kể từ ngày nghiệm thu",
            ["Ky_Han_Thi_Cong"] = "15 ngày",
            ["Dieu_Khoan"] = "Báo giá có hiệu lực 15 ngày. Giá đã bao gồm vận chuyển nội thành.",
            ["Bao_Hanh"] = "12 tháng",
            ["Ghi_Chu"] = "Giao hàng giờ hành chính",
            ["Nguoi_Bao_Gia"] = "Phạm Thu Hà",
            ["Nhan_Vien"] = "Phạm Thu Hà",
            ["MST_Cua_Hang"] = "0312345678",
            ["Dien_Thoai_Chi_Nhanh"] = "0909 123 456",
            ["Ma_Don_Hang"] = "HD000123",
            ["Gio"] = DateTime.UtcNow.AddHours(7).ToString("HH:mm"),
            ["Nguoi_Ban"] = "Phạm Thu Hà",
            ["Ten_Ban"] = "Bàn 5",
            ["Phi_Giao_Hang"] = "30.000",
            ["Phu_Thu"] = "0",
            ["Khach_Can_Tra"] = "24.300.000",
            ["Khach_Thanh_Toan"] = "24.500.000",
            ["Tien_Thua"] = "200.000",
            ["Con_Lai"] = "0",
            ["Logo"] = SampleImage(0x1E, 0x40, 0xAF, 360, 160),
            ["Con_Dau"] = SampleImage(0xDC, 0x26, 0x26, 300, 300),
        };
        var lines = new List<IReadOnlyDictionary<string, string>>
        {
            new Dictionary<string, string>
            {
                ["STT"] = "1", ["Ma_Hang"] = "TB01", ["Ten_Hang_Hoa"] = "Tủ bếp gỗ sồi", ["Don_Vi_Tinh"] = "Bộ",
                ["So_Luong"] = "1", ["Don_Gia"] = "15.000.000", ["Chiet_Khau"] = "0", ["Thanh_Tien"] = "15.000.000",
                ["Chieu_Dai"] = "3.200", ["Chieu_Rong"] = "600", ["Chieu_Cao"] = "850", ["Bao_Hanh"] = "24 tháng", ["Ghi_Chu"] = "Màu vân gỗ",
                ["Hinh_Anh"] = SampleImage(0x16, 0xA3, 0x4A, 200, 200),
            },
            new Dictionary<string, string>
            {
                ["STT"] = "2", ["Ma_Hang"] = "BD02", ["Ten_Hang_Hoa"] = "Mặt đá bếp", ["Don_Vi_Tinh"] = "m",
                ["So_Luong"] = "4", ["Don_Gia"] = "2.000.000", ["Chiet_Khau"] = "0", ["Thanh_Tien"] = "8.000.000",
                ["Chieu_Dai"] = "4.000", ["Chieu_Rong"] = "600", ["Chieu_Cao"] = "20", ["Bao_Hanh"] = "12 tháng", ["Ghi_Chu"] = "",
                ["Hinh_Anh"] = SampleImage(0xEA, 0x58, 0x0C, 200, 200),
            },
        };
        return (data, lines);
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

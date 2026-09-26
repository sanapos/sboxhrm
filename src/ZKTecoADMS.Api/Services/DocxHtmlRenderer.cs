using System.Globalization;
using System.IO.Compression;

using System.Text;
using System.Text.RegularExpressions;
using System.Xml.Linq;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Dựng file Word thành trang HTML giống bản in để SOẠN MẪU trên trình duyệt: giữ đoạn, định dạng chữ,
/// bảng (gộp ô, viền, nền), ảnh, đầu / chân trang, đánh số. Mỗi đoạn có <c>data-pid</c> (khớp
/// <see cref="DocxTemplateEngine"/>), mỗi mẩu chữ có <c>data-o</c> = vị trí ký tự trong chữ GỐC của đoạn →
/// bôi đen trên trang biết chính xác chữ nào trong file. Chỗ đã gắn trường hiện thành ô màu.
/// </summary>
public static class DocxHtmlRenderer
{
    static readonly XNamespace W = "http://schemas.openxmlformats.org/wordprocessingml/2006/main";
    static readonly XNamespace R = "http://schemas.openxmlformats.org/officeDocument/2006/relationships";
    static readonly XNamespace A = "http://schemas.openxmlformats.org/drawingml/2006/main";
    static readonly XNamespace Wp = "http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing";
    static readonly XNamespace V = "urn:schemas-microsoft-com:vml";
    static readonly XNamespace Rel = "http://schemas.openxmlformats.org/package/2006/relationships";
    static readonly Regex LiteralToken = new(@"\{[A-Za-z][A-Za-z0-9_]*\}", RegexOptions.Compiled);

    /// <summary>Vùng đã gắn trong đoạn (vị trí trên chữ gốc).</summary>
    public sealed record Range(int Start, int Length, string Field, string? Text);

    sealed class RunProps
    {
        public bool? Bold, Italic, Strike, Caps;
        public string? Underline, Size, Color, Font, Highlight, Shade, VertAlign;

        public RunProps Clone() => (RunProps)MemberwiseClone();

        public void Apply(XElement? rPr)
        {
            if (rPr == null) return;
            Bold = Flag(rPr.Element(W + "b")) ?? Bold;
            Italic = Flag(rPr.Element(W + "i")) ?? Italic;
            Strike = Flag(rPr.Element(W + "strike")) ?? Strike;
            Caps = Flag(rPr.Element(W + "caps")) ?? Caps;
            if (rPr.Element(W + "u") is { } u) Underline = Val(u) ?? "single";
            if (Val(rPr.Element(W + "sz")) is { } sz && double.TryParse(sz, NumberStyles.Any, CultureInfo.InvariantCulture, out var half))
                Size = (half / 2).ToString("0.#", CultureInfo.InvariantCulture) + "pt";
            if (Val(rPr.Element(W + "color")) is { } c && c != "auto") Color = "#" + c;
            if (rPr.Element(W + "rFonts") is { } f)
                Font = (string?)f.Attribute(W + "ascii") ?? (string?)f.Attribute(W + "hAnsi") ?? (string?)f.Attribute(W + "cs") ?? Font;
            if (Val(rPr.Element(W + "highlight")) is { } h && h != "none") Highlight = HighlightColor(h);
            if (rPr.Element(W + "shd")?.Attribute(W + "fill")?.Value is { } fill && fill != "auto") Shade = "#" + fill;
            if (Val(rPr.Element(W + "vertAlign")) is { } va) VertAlign = va;
        }

        public string Css()
        {
            var sb = new StringBuilder();
            if (Bold == true) sb.Append("font-weight:bold;");
            if (Italic == true) sb.Append("font-style:italic;");
            var deco = new List<string>();
            if (Underline is { } u && u != "none") deco.Add("underline");
            if (Strike == true) deco.Add("line-through");
            if (deco.Count > 0) sb.Append("text-decoration:").Append(string.Join(' ', deco)).Append(';');
            if (Caps == true) sb.Append("text-transform:uppercase;");
            if (Size != null) sb.Append("font-size:").Append(Size).Append(';');
            if (Color != null) sb.Append("color:").Append(Color).Append(';');
            if (Font != null) sb.Append("font-family:'").Append(Font.Replace("'", "")).Append("',serif;");
            if ((Highlight ?? Shade) is { } bg) sb.Append("background:").Append(bg).Append(';');
            if (VertAlign == "superscript") sb.Append("vertical-align:super;font-size:70%;");
            if (VertAlign == "subscript") sb.Append("vertical-align:sub;font-size:70%;");
            return sb.ToString();
        }
    }

    sealed class ParaProps
    {
        public string? Align;
        public double? Before, After, Left, Right, FirstLine, LineHeight;
        public string? Shade;
        public (string NumId, int Level)? Num;

        public ParaProps Clone() => (ParaProps)MemberwiseClone();

        public void Apply(XElement? pPr)
        {
            if (pPr == null) return;
            if (Val(pPr.Element(W + "jc")) is { } jc) Align = jc switch
            {
                "center" => "center",
                "right" or "end" => "right",
                "both" or "distribute" => "justify",
                _ => "left",
            };
            if (pPr.Element(W + "spacing") is { } sp)
            {
                Before = Twips(sp.Attribute(W + "before")) ?? Before;
                After = Twips(sp.Attribute(W + "after")) ?? After;
                if (int.TryParse((string?)sp.Attribute(W + "line"), out var line))
                    LineHeight = ((string?)sp.Attribute(W + "lineRule")) is "exact" or "atLeast"
                        ? -line / 15.0 // âm = đơn vị px
                        : line / 240.0;
            }
            if (pPr.Element(W + "ind") is { } ind)
            {
                Left = Twips(ind.Attribute(W + "left") ?? ind.Attribute(W + "start")) ?? Left;
                Right = Twips(ind.Attribute(W + "right") ?? ind.Attribute(W + "end")) ?? Right;
                if (Twips(ind.Attribute(W + "firstLine")) is { } fl) FirstLine = fl;
                if (Twips(ind.Attribute(W + "hanging")) is { } hg) FirstLine = -hg;
            }
            if (pPr.Element(W + "shd")?.Attribute(W + "fill")?.Value is { } fill && fill != "auto") Shade = "#" + fill;
            if (pPr.Element(W + "numPr") is { } np && Val(np.Element(W + "numId")) is { } numId && numId != "0")
                Num = (numId, int.TryParse(Val(np.Element(W + "ilvl")), out var l) ? l : 0);
        }

        public string Css()
        {
            var sb = new StringBuilder();
            if (Align != null) sb.Append("text-align:").Append(Align).Append(';');
            sb.Append("margin:").Append(Px(Before ?? 0)).Append(' ').Append(Px(Right ?? 0)).Append(' ')
                .Append(Px(After ?? 0)).Append(' ').Append(Px(Left ?? 0)).Append(';');
            if (FirstLine is { } fl && Math.Abs(fl) > 0.1) sb.Append("text-indent:").Append(Px(fl)).Append(';');
            if (LineHeight is { } lh)
                sb.Append("line-height:").Append(lh < 0 ? Px(-lh) : lh.ToString("0.##", CultureInfo.InvariantCulture)).Append(';');
            if (Shade != null) sb.Append("background:").Append(Shade).Append(';');
            return sb.ToString();
        }
    }

    sealed class Ctx
    {
        public required ZipArchive Zip;
        public required IReadOnlyDictionary<string, List<Range>> Ranges;
        public required ISet<string> RemovedRowPids;
        public required IReadOnlyDictionary<string, string> Labels;
        public required ISet<string> LineFields;
        public Dictionary<string, XElement> Styles = [];
        public XElement? DefaultPPr, DefaultRPr;
        public string? DefaultParaStyle;
        public Dictionary<string, (string Fmt, string Text, int Start)[]> Numbering = [];
        public Dictionary<string, int[]> NumCounters = [];
        // Trong một phần (document / header1…): chỉ số đoạn + quan hệ ảnh.
        public string Part = "document";
        public Dictionary<XElement, int> ParaIndex = [];
        public Dictionary<string, string> PartRels = [];
    }

    public static string Render(
        byte[] docx,
        IReadOnlyDictionary<string, List<Range>> ranges,
        ISet<string> removedRowPids,
        IReadOnlyDictionary<string, string> labels,
        ISet<string> lineFields)
    {
        using var zip = new ZipArchive(new MemoryStream(docx), ZipArchiveMode.Read);
        var ctx = new Ctx { Zip = zip, Ranges = ranges, RemovedRowPids = removedRowPids, Labels = labels, LineFields = lineFields };
        LoadStyles(ctx);
        LoadNumbering(ctx);

        var document = LoadXml(zip, "word/document.xml") ?? throw new InvalidOperationException("File Word không hợp lệ.");
        var body = document.Root!.Element(W + "body")!;
        var sect = body.Elements(W + "sectPr").LastOrDefault() ?? body.Descendants(W + "sectPr").LastOrDefault();
        var docRels = LoadRels(zip, "word/_rels/document.xml.rels");

        // Khổ giấy / lề (twips → px).
        double pageW = 794, mL = 76, mR = 76, mT = 76, mB = 76;
        if (sect?.Element(W + "pgSz") is { } pg && Twips(pg.Attribute(W + "w")) is { } pw) pageW = pw;
        if (sect?.Element(W + "pgMar") is { } mar)
        {
            mL = Twips(mar.Attribute(W + "left")) ?? mL;
            mR = Twips(mar.Attribute(W + "right")) ?? mR;
            mT = Twips(mar.Attribute(W + "top")) ?? mT;
            mB = Twips(mar.Attribute(W + "bottom")) ?? mB;
        }

        var baseRun = new RunProps { Font = "Times New Roman", Size = "11pt" };
        baseRun.Apply(ctx.DefaultRPr);

        var html = new StringBuilder();
        html.Append("<!DOCTYPE html><html><head><meta charset=\"utf-8\"><style>")
            .Append(Css(pageW, mL, mR, mT, mB, baseRun))
            .Append("</style></head><body><div class=\"page\">");

        // Đầu trang mặc định.
        if (HeaderFooterPart(sect, "headerReference", docRels) is { } hdr)
            html.Append("<div class=\"hf hdr\">").Append(RenderPart(ctx, hdr)).Append("</div>");

        ctx.Part = "document";
        ctx.ParaIndex = IndexParagraphs(document);
        ctx.PartRels = docRels;
        foreach (var el in body.Elements())
            RenderBlock(ctx, el, html);

        if (HeaderFooterPart(sect, "footerReference", docRels) is { } ftr)
            html.Append("<div class=\"hf ftr\">").Append(RenderPart(ctx, ftr)).Append("</div>");

        html.Append("</div><script>").Append(Script).Append("</script></body></html>");
        return html.ToString();
    }

    // ─── Khối ─────────────────────────────────────────────────────────

    static string RenderPart(Ctx ctx, string partPath)
    {
        var doc = LoadXml(ctx.Zip, partPath);
        if (doc?.Root == null) return "";
        var saved = (ctx.Part, ctx.ParaIndex, ctx.PartRels);
        ctx.Part = Path.GetFileNameWithoutExtension(partPath); // header1 / footer2 — khớp DocxTemplateEngine
        ctx.ParaIndex = IndexParagraphs(doc);
        ctx.PartRels = LoadRels(ctx.Zip, $"word/_rels/{Path.GetFileName(partPath)}.rels");
        var sb = new StringBuilder();
        foreach (var el in doc.Root.Elements()) RenderBlock(ctx, el, sb);
        (ctx.Part, ctx.ParaIndex, ctx.PartRels) = saved;
        return sb.ToString();
    }

    static void RenderBlock(Ctx ctx, XElement el, StringBuilder sb)
    {
        if (el.Name == W + "p") RenderParagraph(ctx, el, sb);
        else if (el.Name == W + "tbl") RenderTable(ctx, el, sb);
        else if (el.Name == W + "sdt")
            foreach (var c in el.Element(W + "sdtContent")?.Elements() ?? []) RenderBlock(ctx, c, sb);
    }

    static void RenderParagraph(Ctx ctx, XElement p, StringBuilder sb)
    {
        var pid = ctx.ParaIndex.TryGetValue(p, out var idx) ? $"{ctx.Part}:{idx}" : "";
        var pPr = p.Element(W + "pPr");
        var styleId = Val(pPr?.Element(W + "pStyle")) ?? ctx.DefaultParaStyle;

        var pp = new ParaProps();
        pp.Apply(ctx.DefaultPPr);
        foreach (var s in StyleChain(ctx, styleId)) pp.Apply(s.Element(W + "pPr"));
        pp.Apply(pPr);

        var rp = new RunProps { Font = "Times New Roman", Size = "11pt" };
        rp.Apply(ctx.DefaultRPr);
        foreach (var s in StyleChain(ctx, styleId)) rp.Apply(s.Element(W + "rPr"));

        sb.Append("<p");
        if (pid.Length > 0) sb.Append(" data-pid=\"").Append(pid).Append('"');
        sb.Append(" style=\"").Append(pp.Css()).Append(rp.Css()).Append("\">");

        if (pp.Num is { } num && NumberPrefix(ctx, num.NumId, num.Level) is { } prefix)
            sb.Append("<span class=\"num\">").Append(Enc(prefix)).Append("</span>");

        var ranges = ctx.Ranges.TryGetValue(pid, out var rs) ? rs.OrderBy(r => r.Start).ToList() : [];
        var emitted = new HashSet<Range>();
        var offset = 0;
        var any = false;
        foreach (var node in p.Descendants())
        {
            // Chỉ phần tử của chính đoạn này (không tính đoạn lồng trong ô chữ).
            if (node.Ancestors(W + "p").FirstOrDefault() != p) continue;
            if (node.Ancestors(W + "drawing").Any() || node.Ancestors(W + "pict").Any()) continue;
            var run = node.Parent;
            if (node.Name == W + "t" && run?.Name == W + "r")
            {
                var text = node.Value;
                var style = RunStyle(ctx, rp, run);
                EmitText(sb, pid, text, offset, ranges, emitted, style, ctx);
                offset += text.Length;
                any |= text.Length > 0;
            }
            else if (node.Name == W + "tab" && run?.Name == W + "r")
                sb.Append("<span class=\"tab\">  </span>");
            else if (node.Name == W + "br" && run?.Name == W + "r")
                sb.Append((string?)node.Attribute(W + "type") == "page" ? "<span class=\"pgbr\"></span>" : "<br>");
            else if (node.Name == W + "drawing" || node.Name == W + "pict")
            {
                AppendImage(ctx, node, sb);
                any = true;
            }
        }
        if (!any) sb.Append("<br>");
        sb.Append("</p>");
    }

    static string RunStyle(Ctx ctx, RunProps paraRun, XElement run)
    {
        var rp = paraRun.Clone();
        var rPr = run.Element(W + "rPr");
        if (Val(rPr?.Element(W + "rStyle")) is { } cs)
            foreach (var s in StyleChain(ctx, cs)) rp.Apply(s.Element(W + "rPr"));
        rp.Apply(rPr);
        return rp.Css();
    }

    /// <summary>Chữ của một w:t: phần tĩnh (có data-o) xen các ô trường đã gắn.</summary>
    static void EmitText(StringBuilder sb, string pid, string text, int offset, List<Range> ranges, HashSet<Range> emitted, string style, Ctx ctx)
    {
        var end = offset + text.Length;
        var pos = offset;
        while (pos < end)
        {
            var cover = ranges.FirstOrDefault(r => r.Start <= pos && pos < r.Start + r.Length);
            if (cover != null)
            {
                if (emitted.Add(cover)) AppendChip(sb, pid, cover, ctx, style);
                pos = Math.Min(end, cover.Start + cover.Length);
                continue;
            }
            var next = ranges.Where(r => r.Start > pos).Select(r => r.Start).DefaultIfEmpty(end).Min();
            var stop = Math.Min(end, next);
            var piece = text.Substring(pos - offset, stop - pos);
            // Mã {Truong} có sẵn trong file (mẫu đã sửa tay) → hiện như ô trường, vẫn giữ vị trí ký tự.
            var last = 0;
            foreach (Match m in LiteralToken.Matches(piece))
            {
                if (m.Index > last) AppendStatic(sb, piece[last..m.Index], pos + last, style);
                var key = m.Value[1..^1];
                var cls = ctx.LineFields.Contains(key) ? "fld lit line" : "fld lit";
                sb.Append("<span class=\"").Append(cls).Append("\" data-o=\"").Append(pos + m.Index)
                    .Append("\" title=\"Mã trường có sẵn trong file\" style=\"").Append(style).Append("\">")
                    .Append(Enc(m.Value)).Append("</span>");
                last = m.Index + m.Length;
            }
            if (last < piece.Length) AppendStatic(sb, piece[last..], pos + last, style);
            pos = stop;
        }
    }

    static void AppendStatic(StringBuilder sb, string text, int offset, string style) =>
        sb.Append("<span class=\"t\" data-o=\"").Append(offset).Append("\" style=\"").Append(style).Append("\">")
          .Append(Enc(text)).Append("</span>");

    static void AppendChip(StringBuilder sb, string pid, Range r, Ctx ctx, string style)
    {
        var (cls, label) = r.Field switch
        {
            DocxTemplateEngine.ClearField => ("fld del", "đã xóa"),
            DocxTemplateEngine.TextField => ("fld edit", r.Text ?? ""),
            _ => (ctx.LineFields.Contains(r.Field) ? "fld line" : "fld",
                ctx.Labels.TryGetValue(r.Field, out var l) ? ShortLabel(l) : r.Field),
        };
        sb.Append("<span class=\"").Append(cls).Append("\" data-pid=\"").Append(pid)
            .Append("\" data-s=\"").Append(r.Start).Append("\" data-l=\"").Append(r.Length)
            .Append("\" data-field=\"").Append(Enc(r.Field)).Append("\" style=\"").Append(style).Append("\">")
            .Append(Enc(label.Length == 0 ? " " : label)).Append("</span>");
    }

    static string ShortLabel(string label)
    {
        var cut = label.IndexOf(" (", StringComparison.Ordinal);
        var s = cut > 0 ? label[..cut] : label;
        return s.Length > 36 ? s[..36] + "…" : s;
    }

    static void RenderTable(Ctx ctx, XElement tbl, StringBuilder sb)
    {
        var tblPr = tbl.Element(W + "tblPr");
        var borders = new Dictionary<string, string>();
        foreach (var s in StyleChain(ctx, Val(tblPr?.Element(W + "tblStyle"))))
            ReadBorders(s.Element(W + "tblPr")?.Element(W + "tblBorders"), borders);
        ReadBorders(tblPr?.Element(W + "tblBorders"), borders);

        var grid = tbl.Element(W + "tblGrid")?.Elements(W + "gridCol")
            .Select(g => Twips(g.Attribute(W + "w")) ?? 0).ToList() ?? [];
        var align = Val(tblPr?.Element(W + "jc"));
        sb.Append("<table style=\"border-collapse:collapse;");
        if (grid.Sum() > 0) sb.Append("width:").Append(Px(grid.Sum())).Append(';');
        if (align is "center") sb.Append("margin-left:auto;margin-right:auto;");
        sb.Append("\">");
        if (grid.Count > 0)
        {
            sb.Append("<colgroup>");
            foreach (var g in grid) sb.Append("<col style=\"width:").Append(Px(g)).Append("\">");
            sb.Append("</colgroup>");
        }

        // Ma trận ô → tính rowspan cho vMerge.
        var rows = tbl.Elements(W + "tr").ToList();
        var cellsByRow = rows.Select(tr =>
        {
            var list = new List<(XElement Tc, int Col, int Span, string? VMerge)>();
            var col = 0;
            foreach (var tc in tr.Elements(W + "tc"))
            {
                var tcPr = tc.Element(W + "tcPr");
                var span = int.TryParse(Val(tcPr?.Element(W + "gridSpan")), out var gs) ? gs : 1;
                var vm = tcPr?.Element(W + "vMerge") is { } v ? (Val(v) ?? "continue") : null;
                list.Add((tc, col, span, vm));
                col += span;
            }
            return list;
        }).ToList();

        for (var ri = 0; ri < rows.Count; ri++)
        {
            var tr = rows[ri];
            var pids = tr.Descendants(W + "p").Select(p => ctx.ParaIndex.TryGetValue(p, out var i) ? $"{ctx.Part}:{i}" : "").ToList();
            var removed = pids.Any(ctx.RemovedRowPids.Contains);
            var isItemRow = pids.Any(pid => ctx.Ranges.TryGetValue(pid, out var rs) && rs.Any(r => ctx.LineFields.Contains(r.Field)))
                || tr.Descendants(W + "t").Any(t => LiteralToken.Matches(t.Value).Any(m => ctx.LineFields.Contains(m.Value[1..^1])));
            var cls = (removed ? "removed-row " : "") + (isItemRow ? "item-row" : "");
            sb.Append("<tr").Append(cls.Length > 0 ? $" class=\"{cls.Trim()}\"" : "").Append('>');
            foreach (var (tc, col, span, vm) in cellsByRow[ri])
            {
                if (vm == "continue") continue;
                var rowspan = 1;
                if (vm == "restart")
                    for (var rj = ri + 1; rj < rows.Count; rj++)
                    {
                        var below = cellsByRow[rj].FirstOrDefault(c => c.Col == col);
                        if (below.Tc == null || below.VMerge != "continue") break;
                        rowspan++;
                    }
                var tcPr = tc.Element(W + "tcPr");
                var cellBorders = new Dictionary<string, string>(borders);
                ReadBorders(tcPr?.Element(W + "tcBorders"), cellBorders);
                sb.Append("<td");
                if (span > 1) sb.Append(" colspan=\"").Append(span).Append('"');
                if (rowspan > 1) sb.Append(" rowspan=\"").Append(rowspan).Append('"');
                sb.Append(" style=\"padding:1px 5px;");
                foreach (var side in new[] { "top", "bottom", "left", "right" })
                {
                    var key = side;
                    if (!cellBorders.ContainsKey(side))
                        key = side is "top" or "bottom" ? "insideH" : "insideV";
                    sb.Append("border-").Append(side).Append(':')
                        .Append(cellBorders.TryGetValue(key, out var b) ? b : "none").Append(';');
                }
                if (tcPr?.Element(W + "shd")?.Attribute(W + "fill")?.Value is { } fill && fill != "auto")
                    sb.Append("background:#").Append(fill).Append(';');
                if (Val(tcPr?.Element(W + "vAlign")) is { } va)
                    sb.Append("vertical-align:").Append(va == "center" ? "middle" : va == "bottom" ? "bottom" : "top").Append(';');
                else sb.Append("vertical-align:top;");
                sb.Append("\">");
                foreach (var el in tc.Elements()) RenderBlock(ctx, el, sb);
                sb.Append("</td>");
            }
            sb.Append("</tr>");
        }
        sb.Append("</table>");
    }

    static void ReadBorders(XElement? el, Dictionary<string, string> into)
    {
        if (el == null) return;
        foreach (var b in el.Elements())
        {
            var side = b.Name.LocalName switch { "start" => "left", "end" => "right", var n => n };
            var val = (string?)b.Attribute(W + "val");
            if (val is null or "nil" or "none")
            {
                into[side] = "none";
                continue;
            }
            var sz = int.TryParse((string?)b.Attribute(W + "sz"), out var s8) ? Math.Max(1, s8 / 8.0 * 96 / 72) : 1;
            var color = (string?)b.Attribute(W + "color") is { } c && c != "auto" ? "#" + c : "#000";
            var style = val switch { "double" => "double", "dashed" => "dashed", "dotted" => "dotted", _ => "solid" };
            into[side] = $"{sz.ToString("0.#", CultureInfo.InvariantCulture)}px {style} {color}";
        }
    }

    static void AppendImage(Ctx ctx, XElement node, StringBuilder sb)
    {
        var rid = node.Descendants(A + "blip").Select(b => (string?)b.Attribute(R + "embed")).FirstOrDefault(x => x != null)
            ?? node.Descendants(V + "imagedata").Select(b => (string?)b.Attribute(R + "id")).FirstOrDefault(x => x != null);
        if (rid == null || !ctx.PartRels.TryGetValue(rid, out var target)) return;
        var path = target.StartsWith('/') ? target.TrimStart('/') : "word/" + target;
        var entry = ctx.Zip.GetEntry(path.Replace("\\", "/"));
        if (entry == null || entry.Length > 5_000_000) return;
        var ext = Path.GetExtension(path).ToLowerInvariant();
        var mime = ext switch { ".png" => "image/png", ".jpg" or ".jpeg" => "image/jpeg", ".gif" => "image/gif", ".bmp" => "image/bmp", _ => null };
        if (mime == null) return; // emf / wmf: trình duyệt không hiển thị được
        using var ms = new MemoryStream();
        using (var s = entry.Open()) s.CopyTo(ms);
        var ext2 = node.Descendants(Wp + "extent").FirstOrDefault();
        var w = long.TryParse((string?)ext2?.Attribute("cx"), out var cx) ? cx / 9525.0 : 0;
        var h = long.TryParse((string?)ext2?.Attribute("cy"), out var cy) ? cy / 9525.0 : 0;
        sb.Append("<img src=\"data:").Append(mime).Append(";base64,").Append(Convert.ToBase64String(ms.ToArray())).Append('"');
        if (w > 0) sb.Append(" width=\"").Append(Math.Round(w)).Append('"');
        if (h > 0) sb.Append(" height=\"").Append(Math.Round(h)).Append('"');
        sb.Append('>');
    }

    // ─── Kiểu / đánh số ───────────────────────────────────────────────

    static void LoadStyles(Ctx ctx)
    {
        var styles = LoadXml(ctx.Zip, "word/styles.xml")?.Root;
        if (styles == null) return;
        ctx.DefaultPPr = styles.Element(W + "docDefaults")?.Element(W + "pPrDefault")?.Element(W + "pPr");
        ctx.DefaultRPr = styles.Element(W + "docDefaults")?.Element(W + "rPrDefault")?.Element(W + "rPr");
        foreach (var s in styles.Elements(W + "style"))
        {
            var id = (string?)s.Attribute(W + "styleId");
            if (id == null) continue;
            ctx.Styles[id] = s;
            if ((string?)s.Attribute(W + "type") == "paragraph" && (string?)s.Attribute(W + "default") is "1" or "true")
                ctx.DefaultParaStyle = id;
        }
    }

    /// <summary>Chuỗi kiểu từ gốc (basedOn) → kiểu đang dùng.</summary>
    static IEnumerable<XElement> StyleChain(Ctx ctx, string? id)
    {
        var chain = new List<XElement>();
        var guard = 0;
        while (id != null && ctx.Styles.TryGetValue(id, out var s) && guard++ < 10)
        {
            chain.Add(s);
            id = Val(s.Element(W + "basedOn"));
        }
        chain.Reverse();
        return chain;
    }

    static void LoadNumbering(Ctx ctx)
    {
        var root = LoadXml(ctx.Zip, "word/numbering.xml")?.Root;
        if (root == null) return;
        var abstracts = root.Elements(W + "abstractNum").ToDictionary(
            a => (string?)a.Attribute(W + "abstractNumId") ?? "",
            a => a.Elements(W + "lvl").OrderBy(l => (int?)l.Attribute(W + "ilvl") ?? 0).Select(l => (
                Fmt: Val(l.Element(W + "numFmt")) ?? "decimal",
                Text: Val(l.Element(W + "lvlText")) ?? "",
                Start: int.TryParse(Val(l.Element(W + "start")), out var st) ? st : 1)).ToArray());
        foreach (var n in root.Elements(W + "num"))
        {
            var id = (string?)n.Attribute(W + "numId");
            var abs = Val(n.Element(W + "abstractNumId"));
            if (id != null && abs != null && abstracts.TryGetValue(abs, out var lv)) ctx.Numbering[id] = lv;
        }
    }

    static string? NumberPrefix(Ctx ctx, string numId, int level)
    {
        if (!ctx.Numbering.TryGetValue(numId, out var levels) || level >= levels.Length) return null;
        if (!ctx.NumCounters.TryGetValue(numId, out var counters))
            ctx.NumCounters[numId] = counters = levels.Select(l => l.Start - 1).ToArray();
        counters[level]++;
        for (var i = level + 1; i < counters.Length; i++) counters[i] = levels[i].Start - 1;
        var lvl = levels[level];
        if (lvl.Fmt == "bullet") return "•  ";
        if (lvl.Fmt == "none") return null;
        var text = Regex.Replace(lvl.Text, @"%(\d)", m =>
        {
            var i = m.Groups[1].Value[0] - '1';
            return i >= 0 && i < counters.Length ? Format(Math.Max(counters[i], levels[i].Start), levels[i].Fmt) : "";
        });
        return text + " ";
    }

    static string Format(int n, string fmt) => fmt switch
    {
        "lowerLetter" => ((char)('a' + (n - 1) % 26)).ToString(),
        "upperLetter" => ((char)('A' + (n - 1) % 26)).ToString(),
        "lowerRoman" => Roman(n).ToLowerInvariant(),
        "upperRoman" => Roman(n),
        _ => n.ToString(CultureInfo.InvariantCulture),
    };

    static string Roman(int n)
    {
        var map = new[] { (1000, "M"), (900, "CM"), (500, "D"), (400, "CD"), (100, "C"), (90, "XC"), (50, "L"), (40, "XL"), (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I") };
        var sb = new StringBuilder();
        foreach (var (v, s) in map)
            while (n >= v) { sb.Append(s); n -= v; }
        return sb.ToString();
    }

    // ─── Tiện ích ─────────────────────────────────────────────────────

    static Dictionary<XElement, int> IndexParagraphs(XDocument doc)
    {
        var map = new Dictionary<XElement, int>();
        var i = 0;
        foreach (var p in doc.Descendants(W + "p")) map[p] = i++;
        return map;
    }

    static string? HeaderFooterPart(XElement? sect, string refName, Dictionary<string, string> rels)
    {
        var r = sect?.Elements(W + refName).FirstOrDefault(x => (string?)x.Attribute(W + "type") is "default" or null);
        var id = (string?)r?.Attribute(R + "id");
        return id != null && rels.TryGetValue(id, out var target) ? "word/" + target.TrimStart('/') : null;
    }

    static XDocument? LoadXml(ZipArchive zip, string path)
    {
        var e = zip.GetEntry(path);
        if (e == null) return null;
        using var s = e.Open();
        return XDocument.Load(s, LoadOptions.PreserveWhitespace);
    }

    static Dictionary<string, string> LoadRels(ZipArchive zip, string path)
    {
        var doc = LoadXml(zip, path);
        return doc?.Root?.Elements(Rel + "Relationship")
            .Where(r => (string?)r.Attribute("TargetMode") != "External")
            .ToDictionary(r => (string?)r.Attribute("Id") ?? "", r => (string?)r.Attribute("Target") ?? "")
            ?? [];
    }

    static string? Val(XElement? e) => (string?)e?.Attribute(W + "val");

    static bool? Flag(XElement? e)
    {
        if (e == null) return null;
        var v = (string?)e.Attribute(W + "val");
        return v is null or "1" or "true" or "on";
    }

    static double? Twips(XAttribute? a) =>
        a != null && double.TryParse(a.Value, NumberStyles.Any, CultureInfo.InvariantCulture, out var t) ? t / 15.0 : null;

    static string Px(double v) => v.ToString("0.#", CultureInfo.InvariantCulture) + "px";

    /// <summary>Chỉ mã hóa ký tự đặc biệt HTML — giữ nguyên chữ tiếng Việt (WebUtility mã hóa cả «ô», «á»).</summary>
    static string Enc(string s)
    {
        if (s.IndexOfAny(['<', '>', '&', '"', '\'']) < 0) return s;
        var sb = new StringBuilder(s.Length + 16);
        foreach (var c in s)
            sb.Append(c switch { '<' => "&lt;", '>' => "&gt;", '&' => "&amp;", '"' => "&quot;", '\'' => "&#39;", _ => c.ToString() });
        return sb.ToString();
    }

    static string HighlightColor(string name) => name switch
    {
        "yellow" => "#ffff00", "green" => "#00ff00", "cyan" => "#00ffff", "magenta" => "#ff00ff",
        "blue" => "#0000ff", "red" => "#ff0000", "darkBlue" => "#000080", "darkCyan" => "#008080",
        "darkGreen" => "#008000", "darkMagenta" => "#800080", "darkRed" => "#800000", "darkYellow" => "#808000",
        "darkGray" => "#808080", "lightGray" => "#c0c0c0", "black" => "#000000", _ => "#ffff00",
    };

    static string Css(double pageW, double mL, double mR, double mT, double mB, RunProps baseRun) => $$"""
        html,body{margin:0;background:#e5e7eb}
        .page{box-sizing:border-box;width:{{Px(pageW)}};min-height:{{Px(pageW * 1.414)}};margin:12px auto;background:#fff;
          padding:{{Px(mT)}} {{Px(mR)}} {{Px(mB)}} {{Px(mL)}};box-shadow:0 1px 6px rgba(0,0,0,.25);{{baseRun.Css()}}}
        p{white-space:pre-wrap;word-wrap:break-word;min-height:1em}
        table{margin:2px 0} td p{margin:0}
        .hf{opacity:.75;border-bottom:1px dashed #cbd5e1;margin-bottom:8px}.ftr{border-top:1px dashed #cbd5e1;border-bottom:none;margin-top:8px}
        .t{cursor:text}
        .t:hover{background:rgba(59,130,246,.08)}
        .fld{background:#fde68a;border-radius:3px;padding:0 3px;box-shadow:inset 0 0 0 1px #f59e0b;cursor:pointer;white-space:nowrap}
        .fld.line{background:#bae6fd;box-shadow:inset 0 0 0 1px #0284c7}
        .fld.edit{background:#dcfce7;box-shadow:inset 0 0 0 1px #16a34a;white-space:pre-wrap}
        .fld.del{background:#fee2e2;box-shadow:inset 0 0 0 1px #dc2626;color:#991b1b;text-decoration:line-through;font-size:80%}
        .fld.lit{background:#ede9fe;box-shadow:inset 0 0 0 1px #7c3aed;cursor:default}
        .fld.sel,.t.sel{outline:2px solid #2563eb}
        tr.item-row>td{box-shadow:inset 0 0 0 9999px rgba(14,165,233,.08)}
        tr.removed-row>td{opacity:.35;text-decoration:line-through}
        .num{user-select:none}
        .tab{user-select:none}
        .pgbr{display:block;border-top:2px dashed #94a3b8;margin:10px 0}
        ::selection{background:#bfdbfe}
        """;

    /// <summary>JS trong khung soạn: báo lên trang cha vùng bôi đen / ô trường / đoạn được bấm.</summary>
    const string Script = """
        (function(){
          function post(m){ m.src='sbox-docx'; try{ parent.postMessage(JSON.stringify(m),'*'); }catch(e){} }
          function para(n){ var el=n&&(n.nodeType===3?n.parentElement:n); return el?el.closest('[data-pid]'):null; }
          function pos(node, off, atEnd){
            var el=node.nodeType===3?node.parentElement:node;
            var span=el&&el.closest('[data-o]');
            if(span && node.nodeType===3) return {p:para(span), o:(+span.dataset.o)+off};
            if(span) return {p:para(span), o:(+span.dataset.o)+(atEnd?span.textContent.length:0)};
            // Ranh giới phần tử: lấy mẩu chữ gần nhất trong đoạn.
            var p=para(el); if(!p) return null;
            var kids=node.nodeType===1?node.childNodes:[]; var k=kids[off]||kids[off-1];
            var s=k&&(k.nodeType===1?(k.matches&&k.matches('[data-o]')?k:k.querySelector&&k.querySelector('[data-o]')):null);
            if(!s) return null;
            return {p:p, o:(+s.dataset.o)+(atEnd&&kids[off]!==k?s.textContent.length:0)};
          }
          document.addEventListener('mouseup', function(e){
            if(e.button!==0) return;
            if(e.target.closest('.fld:not(.lit)')) return;
            var sel=window.getSelection(); if(!sel||sel.isCollapsed||!sel.rangeCount) return;
            var r=sel.getRangeAt(0);
            var a=pos(r.startContainer,r.startOffset,false), b=pos(r.endContainer,r.endOffset,true);
            if(!a||!b||!a.p||a.p!==b.p){ post({type:'warn',msg:'Chỉ bôi đen trong MỘT đoạn / MỘT ô.'}); return; }
            if(b.o<=a.o) return;
            var tr=a.p.closest('tr'); var rect=r.getBoundingClientRect();
            post({type:'select', pid:a.p.dataset.pid, start:a.o, end:b.o, text:sel.toString(),
                  inTable:!!tr, rowRemoved:!!(tr&&tr.classList.contains('removed-row')), x:rect.left, y:rect.bottom});
          });
          document.addEventListener('click', function(e){
            var c=e.target.closest('.fld:not(.lit)');
            if(!c) return;
            document.querySelectorAll('.sel').forEach(function(x){x.classList.remove('sel');});
            c.classList.add('sel');
            var tr=c.closest('tr');
            post({type:'chip', pid:c.dataset.pid, start:+c.dataset.s, len:+c.dataset.l, field:c.dataset.field,
                  inTable:!!tr, rowRemoved:!!(tr&&tr.classList.contains('removed-row'))});
          });
          document.addEventListener('contextmenu', function(e){
            var p=para(e.target); if(!p) return;
            e.preventDefault();
            var tr=p.closest('tr');
            post({type:'para', pid:p.dataset.pid, inTable:!!tr, rowRemoved:!!(tr&&tr.classList.contains('removed-row'))});
          });
          window.addEventListener('load', function(){ post({type:'ready'}); });
        })();
        """;
}

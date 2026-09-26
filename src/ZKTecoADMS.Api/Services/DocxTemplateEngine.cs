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
    /// <summary>Trường đặc biệt: xóa cụm chữ (phần thừa của giá trị bị ngắt dòng).</summary>
    public const string ClearField = "_Xoa";

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
                    var value = r.Field == ClearField ? "" : "{" + r.Field + "}";
                    if (ReplaceInParagraph(paragraphs[i], r.Find, value))
                        applied.Add(r);
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
        };
        var lines = new List<IReadOnlyDictionary<string, string>>
        {
            new Dictionary<string, string>
            {
                ["STT"] = "1", ["Ma_Hang"] = "TB01", ["Ten_Hang_Hoa"] = "Tủ bếp gỗ sồi", ["Don_Vi_Tinh"] = "Bộ",
                ["So_Luong"] = "1", ["Don_Gia"] = "15.000.000", ["Chiet_Khau"] = "0", ["Thanh_Tien"] = "15.000.000",
                ["Chieu_Dai"] = "3.200", ["Chieu_Rong"] = "600", ["Chieu_Cao"] = "850", ["Bao_Hanh"] = "24 tháng", ["Ghi_Chu"] = "Màu vân gỗ",
            },
            new Dictionary<string, string>
            {
                ["STT"] = "2", ["Ma_Hang"] = "BD02", ["Ten_Hang_Hoa"] = "Mặt đá bếp", ["Don_Vi_Tinh"] = "m",
                ["So_Luong"] = "4", ["Don_Gia"] = "2.000.000", ["Chiet_Khau"] = "0", ["Thanh_Tien"] = "8.000.000",
                ["Chieu_Dai"] = "4.000", ["Chieu_Rong"] = "600", ["Chieu_Cao"] = "20", ["Bao_Hanh"] = "12 tháng", ["Ghi_Chu"] = "",
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

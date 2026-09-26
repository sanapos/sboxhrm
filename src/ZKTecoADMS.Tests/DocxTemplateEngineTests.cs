using System.IO.Compression;
using System.Text;
using System.Xml.Linq;
using Xunit;
using ZKTecoADMS.Api.Services;

namespace ZKTecoADMS.Tests;

public class DocxTemplateEngineTests
{
    const string Ns = "http://schemas.openxmlformats.org/wordprocessingml/2006/main";

    static string P(params string[] runs) =>
        "<w:p>" + string.Concat(runs.Select(r => $"<w:r><w:rPr><w:b/></w:rPr><w:t xml:space=\"preserve\">{r}</w:t></w:r>")) + "</w:p>";

    static string Row(params string[] cells) =>
        "<w:tr>" + string.Concat(cells.Select(c => $"<w:tc>{P(c)}</w:tc>")) + "</w:tr>";

    /// <summary>Mẫu báo giá: tên khách bị Word tách 2 run; bảng tiêu đề + 2 dòng mẫu + dòng tổng.</summary>
    static byte[] SampleDocx()
    {
        var body =
            P("BÁO GIÁ SỐ: ", "BG-001") +
            P("Kính gửi: Công ty ", "TNHH Minh An") +
            "<w:tbl>" +
            Row("STT", "Hạng mục", "Thành tiền") +
            Row("1", "Tủ bếp gỗ", "15.000.000") +
            Row("2", "Bàn đá", "8.000.000") +
            Row("", "Tổng cộng", "23.000.000") +
            "</w:tbl>" +
            P("Ghi chú: ……………");
        var xml = $"<?xml version=\"1.0\" encoding=\"UTF-8\"?><w:document xmlns:w=\"{Ns}\"><w:body>{body}</w:body></w:document>";
        using var ms = new MemoryStream();
        using (var zip = new ZipArchive(ms, ZipArchiveMode.Create, true))
        {
            using (var s = new StreamWriter(zip.CreateEntry("word/document.xml").Open(), new UTF8Encoding(false)))
                s.Write(xml);
            using (var s2 = new StreamWriter(zip.CreateEntry("word/styles.xml").Open()))
                s2.Write($"<w:styles xmlns:w=\"{Ns}\"/>");
        }
        return ms.ToArray();
    }

    static List<string> Texts(byte[] docx) => DocxTemplateEngine.ExtractParagraphs(docx).Select(p => p.Text).ToList();

    [Fact]
    public void Apply_and_render_keep_layout_clone_item_rows_and_drop_sample_rows()
    {
        var docx = SampleDocx();
        var paras = DocxTemplateEngine.ExtractParagraphs(docx);
        string Id(string text) => paras.First(p => p.Text == text).Id;

        var (tpl, applied) = DocxTemplateEngine.ApplyReplacements(docx,
        [
            new(Id("BÁO GIÁ SỐ: BG-001"), "BG-001", "Ma_Bao_Gia"),
            new(Id("Kính gửi: Công ty TNHH Minh An"), "Công ty TNHH Minh An", "Ten_Cong_Ty_Khach"), // trải 2 run
            new(Id("1"), "1", "STT"),
            new(Id("Tủ bếp gỗ"), "Tủ bếp gỗ", "Ten_Hang_Hoa"),
            new(Id("15.000.000"), "15.000.000", "Thanh_Tien"),
            new(Id("23.000.000"), "23.000.000", "Tong_Cong"),
            new(Id("Ghi chú: ……………"), "……………", "Ghi_Chu"),
            new(Id("Ghi chú: ……………"), "không có", "Ghi_Chu"), // cụm không tồn tại → bỏ
        ],
        [Id("Bàn đá")]);

        Assert.Equal(7, applied.Count);
        var tplTexts = Texts(tpl);
        Assert.Contains("Kính gửi: {Ten_Cong_Ty_Khach}", tplTexts);
        Assert.DoesNotContain("Bàn đá", tplTexts); // dòng mẫu thừa đã xóa
        Assert.Contains("Tổng cộng", tplTexts); // dòng tổng giữ nguyên

        var output = DocxTemplateEngine.Render(tpl,
            new Dictionary<string, string>
            {
                ["Ma_Bao_Gia"] = "BG25090001",
                ["Ten_Cong_Ty_Khach"] = "Công ty CP Hòa Bình",
                ["Tong_Cong"] = "30.500.000",
                ["Ghi_Chu"] = "Giao trong 7 ngày\nBảo hành 12 tháng",
                ["Con_Dau"] = "<img src=\"x\"/>",
            },
            [
                new Dictionary<string, string> { ["STT"] = "1", ["Ten_Hang_Hoa"] = "Sofa", ["Thanh_Tien"] = "20.000.000" },
                new Dictionary<string, string> { ["STT"] = "2", ["Ten_Hang_Hoa"] = "Kệ TV", ["Thanh_Tien"] = "10.500.000" },
            ]);

        var texts = Texts(output);
        Assert.Contains("BÁO GIÁ SỐ: BG25090001", texts);
        Assert.Contains("Kính gửi: Công ty CP Hòa Bình", texts);
        Assert.Equal(["STT", "Hạng mục", "Thành tiền", "1", "Sofa", "20.000.000", "2", "Kệ TV", "10.500.000", "Tổng cộng", "30.500.000"],
            texts.Skip(2).Take(11).ToList());
        Assert.Contains("Ghi chú: Giao trong 7 ngàyBảo hành 12 tháng", texts); // xuống dòng = w:br

        // Định dạng run (in đậm) còn nguyên; xuống dòng là w:br.
        using var zip = new ZipArchive(new MemoryStream(output));
        var doc = XDocument.Load(zip.GetEntry("word/document.xml")!.Open());
        XNamespace w = Ns;
        Assert.All(doc.Descendants(w + "r").Where(r => r.Element(w + "t")?.Value.Length > 0),
            r => Assert.NotNull(r.Element(w + "rPr")?.Element(w + "b")));
        Assert.Single(doc.Descendants(w + "br"));
        Assert.NotNull(zip.GetEntry("word/styles.xml")); // phần khác của file được giữ
    }

    [Fact]
    public void Render_joins_tokens_split_across_runs_and_keeps_unknown_tokens()
    {
        var body = P("Khách: {Khach", "_Hang}") + P("Mã lạ: {Khong_Co}");
        var xml = $"<w:document xmlns:w=\"{Ns}\"><w:body>{body}</w:body></w:document>";
        using var ms = new MemoryStream();
        using (var zip = new ZipArchive(ms, ZipArchiveMode.Create, true))
        using (var s = new StreamWriter(zip.CreateEntry("word/document.xml").Open()))
            s.Write(xml);

        var output = DocxTemplateEngine.Render(ms.ToArray(),
            new Dictionary<string, string> { ["Khach_Hang"] = "Chị Lan" }, []);
        var texts = Texts(output);
        Assert.Equal(["Khách: Chị Lan", "Mã lạ: {Khong_Co}"], texts);
    }

    [Fact]
    public void Validate_strips_units_and_propagates_identity_values_to_signatures()
    {
        var paras = new List<DocxParagraph>
        {
            new("document:0", "Đại diện là: (Ông) Nguyễn Hoài Sang", false),
            new("document:1", "Giá trị hợp đồng: 93.645.370 VNĐ, tạm ứng 50%", false),
            new("document:2", "ĐẠI DIỆN CÔNG TY TNHH SANA POS", true),
            new("document:3", "Nguyễn Hoài Sang", true),
            new("document:4", "Địa chỉ: Tỉnh Hà Nam, đường Nguyễn Hoài Sang kéo dài đến cuối khu công nghiệp", false),
            new("document:5", "CÔNG TY TNHH SANA POS", false),
        };
        const string json = """
            {"replacements":[
               {"id":"document:0","find":"(Ông) Nguyễn Hoài Sang","field":"Nguoi_Dai_Dien_Cua_Hang"},
               {"id":"document:1","find":"93.645.370 VNĐ","field":"Tong_Cong"},
               {"id":"document:1","find":"50%","field":"Phan_Tram_Coc"},
               {"id":"document:5","find":"Công ty TNHH SANA POS","field":"Ten_Cong_Ty"}]}
            """;
        var a = PosDocxTemplateAiService.Validate(json, paras);
        Assert.Contains(a.Replacements, r => r.Field == "Tong_Cong" && r.Find == "93.645.370");
        Assert.Contains(a.Replacements, r => r.Field == "Phan_Tram_Coc" && r.Find == "50");
        // Lan sang khối chữ ký (không phân biệt hoa thường, bỏ danh xưng).
        Assert.Contains(a.Replacements, r => r.ParagraphId == "document:3" && r.Field == "Nguoi_Dai_Dien_Cua_Hang");
        Assert.Contains(a.Replacements, r => r.ParagraphId == "document:2" && r.Find == "CÔNG TY TNHH SANA POS");
        // Tên người không lan vào đoạn dài (trùng tên đường / địa danh).
        Assert.DoesNotContain(a.Replacements, r => r.ParagraphId == "document:4");
    }

    [Fact]
    public void Clear_field_removes_text_and_unmapped_sample_cells_are_blanked()
    {
        var body = P("CÔNG TY TNHH SX TM MTV") + P("THỦY LIÊN PHÁT") +
                   "<w:tbl>" + Row("1", "Panel nhôm", "7,20", "CĐT xử lý nền") + "</w:tbl>";
        var xml = $"<w:document xmlns:w=\"{Ns}\"><w:body>{body}</w:body></w:document>";
        using var ms = new MemoryStream();
        using (var zip = new ZipArchive(ms, ZipArchiveMode.Create, true))
        using (var s = new StreamWriter(zip.CreateEntry("word/document.xml").Open()))
            s.Write(xml);
        var docx = ms.ToArray();
        var paras = DocxTemplateEngine.ExtractParagraphs(docx);
        string Id(string t) => paras.First(p => p.Text == t).Id;

        var (tpl, _) = DocxTemplateEngine.ApplyReplacements(docx,
        [
            new(Id("CÔNG TY TNHH SX TM MTV"), "CÔNG TY TNHH SX TM MTV", "Ten_Cong_Ty"),
            new(Id("THỦY LIÊN PHÁT"), "THỦY LIÊN PHÁT", DocxTemplateEngine.ClearField),
            new(Id("1"), "1", "STT"),
            new(Id("Panel nhôm"), "Panel nhôm", "Ten_Hang_Hoa"),
        ]);
        Assert.Equal(["{Ten_Cong_Ty}", "{STT}", "{Ten_Hang_Hoa}"], Texts(tpl));
    }

    [Fact]
    public void Validate_drops_unknown_fields_missing_text_and_bad_ids()
    {
        var paras = new List<DocxParagraph>
        {
            new("document:0", "Kính gửi: Công ty ABC", false),
            new("document:3", "Tủ bếp", true),
        };
        const string json = """
            {"replacements":[
               {"id":"document:0","find":"Công ty ABC","field":"Ten_Cong_Ty_Khach"},
               {"id":"document:0","find":"XYZ","field":"Khach_Hang"},
               {"id":"document:0","find":"ABC","field":"Truong_La"},
               {"id":"document:9","find":"x","field":"Khach_Hang"}],
             "itemRow":[{"id":"document:3","find":"Tủ bếp","field":"Ten_Hang_Hoa"},
                        {"id":"document:3","find":"Tủ bếp","field":"Ten_Cong_Ty_Khach"}],
             "extraItemRowIds":["document:3","document:99"]}
            """;
        var a = PosDocxTemplateAiService.Validate(json, paras);
        Assert.Equal(2, a.Replacements.Count);
        Assert.Contains(a.Replacements, r => r.Field == "Ten_Hang_Hoa");
        Assert.Equal(["document:3"], a.RemoveRowParagraphIds);
    }

    [Fact]
    public void Highlight_shows_field_labels_and_keeps_fixed_text()
    {
        var docx = SampleDocx();
        var paras = DocxTemplateEngine.ExtractParagraphs(docx);
        string Id(string text) => paras.First(p => p.Text == text).Id;
        var (tpl, _) = DocxTemplateEngine.ApplyReplacements(docx,
        [
            new(Id("Kính gửi: Công ty TNHH Minh An"), "Công ty TNHH Minh An", "Ten_Cong_Ty_Khach"),
            new(Id("Tủ bếp gỗ"), "Tủ bếp gỗ", "Ten_Hang_Hoa"),
        ]);
        var shown = DocxTemplateEngine.HighlightFields(tpl, new Dictionary<string, string>
        {
            ["Ten_Cong_Ty_Khach"] = "Tên công ty khách hàng (bên A / bên mua)",
            ["Ten_Hang_Hoa"] = "Tên hàng hóa",
        });
        var texts = Texts(shown);
        Assert.Contains("Kính gửi: [Tên công ty khách hàng]", texts);
        Assert.Contains("[Tên hàng hóa]", texts);
        Assert.DoesNotContain(texts, t => t.Contains('{'));

        using var zip = new ZipArchive(new MemoryStream(shown));
        var xml = new StreamReader(zip.GetEntry("word/document.xml")!.Open()).ReadToEnd();
        Assert.Contains("w:highlight w:val=\"yellow\"", xml);
        Assert.Contains("w:highlight w:val=\"cyan\"", xml); // dòng hàng
    }

    [Fact]
    public void Sample_data_fills_every_catalog_field()
    {
        var (data, lines) = DocxTemplateEngine.SampleData();
        foreach (var key in PosDocxTemplateAiService.DocumentFields.Keys.Where(k => k != "_Xoa"))
            Assert.True(data.ContainsKey(key), key);
        foreach (var key in PosDocxTemplateAiService.LineFields.Keys)
            Assert.True(lines[0].ContainsKey(key), key);
    }

    [Fact]
    public void Editor_html_marks_paragraph_offsets_and_field_chips()
    {
        var docx = SampleDocx();
        var paras = DocxTemplateEngine.ExtractParagraphs(docx);
        var pid = paras.First(p => p.Text == "Kính gửi: Công ty TNHH Minh An").Id;
        var html = DocxHtmlRenderer.Render(docx,
            new Dictionary<string, List<DocxHtmlRenderer.Range>> { [pid] = [new(10, 20, "Ten_Cong_Ty_Khach", null)] },
            new HashSet<string>(),
            new Dictionary<string, string> { ["Ten_Cong_Ty_Khach"] = "Tên công ty khách hàng (bên A)" },
            PosDocxTemplateAiService.LineFields.Keys.ToHashSet());
        Assert.Contains($"data-pid=\"{pid}\"", html);
        Assert.Contains("data-o=\"0\"", html);                 // "Kính gửi: " bắt đầu ở 0
        Assert.Contains("data-field=\"Ten_Cong_Ty_Khach\"", html);
        Assert.Contains(">Tên công ty khách hàng</span>", html);
        Assert.DoesNotContain("TNHH Minh An", html);             // chữ đã gắn không còn hiện
        Assert.Contains("<table", html);
    }

    [Fact]
    public void Resolve_ranges_uses_chosen_occurrence_and_never_overlaps()
    {
        var text = "Bên A: An — đại diện An";
        var r = DocxTemplateEngine.ResolveRanges(text,
        [
            new("p", "An", "Nguoi_Dai_Dien_Khach", Start: 21),   // lần thứ 2 đúng như đã chọn
            new("p", "An", "Khach_Hang"),                         // không vị trí → lần đầu còn trống
            new("p", "An", "Ghi_Chu"),                            // hết chỗ → bỏ
        ]);
        Assert.Equal([21, 7], r.Select(x => x.Start!.Value));
    }

    /// <summary>Chạy tay: SBOX_DOCX_SAMPLE=đường dẫn .docx → ghi HTML trang soạn ra SBOX_DOCX_OUT.</summary>
    [Fact]
    public void Render_local_sample_when_requested()
    {
        var path = Environment.GetEnvironmentVariable("SBOX_DOCX_SAMPLE");
        var outPath = Environment.GetEnvironmentVariable("SBOX_DOCX_OUT");
        if (string.IsNullOrEmpty(path) || string.IsNullOrEmpty(outPath) || !File.Exists(path)) return;
        var html = DocxHtmlRenderer.Render(File.ReadAllBytes(path), new Dictionary<string, List<DocxHtmlRenderer.Range>>(),
            new HashSet<string>(), new Dictionary<string, string>(), new HashSet<string>());
        File.WriteAllText(outPath, html);
    }
}

using System.Text;
using ClosedXML.Excel;
using Xunit;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Api.Services;

namespace ZKTecoADMS.Tests;

/// <summary>Nhập Excel thường (tiêu đề đồng nghĩa, giá định dạng, khớp tên) và đọc bảng tính cho AI (TSV + giới hạn).</summary>
public class PosProductExcelImportTests
{
    static MemoryStream Save(XLWorkbook wb)
    {
        var ms = new MemoryStream();
        wb.SaveAs(ms);
        ms.Position = 0;
        return ms;
    }

    // ===== Nhập Excel thường (mục 5) =====

    [Fact]
    public void Parser_finds_header_synonyms_below_title_rows_and_reads_vietnamese_prices()
    {
        using var wb = new XLWorkbook();
        var ws = wb.Worksheets.Add("Menu");
        ws.Cell(1, 1).Value = "MENU QUÁN CÀ PHÊ ABC";
        ws.Cell(2, 1).Value = "Địa chỉ: 12 Lê Lợi";
        ws.Cell(4, 1).Value = "STT";
        ws.Cell(4, 2).Value = "Tên món";
        ws.Cell(4, 3).Value = "Đơn giá";
        ws.Cell(4, 4).Value = "ĐVT";
        ws.Cell(4, 5).Value = "Danh mục";
        ws.Cell(4, 6).Value = "Giá nhập";
        ws.Cell(4, 7).Value = "SL tồn";

        ws.Cell(5, 2).Value = "Cà phê sữa";
        ws.Cell(5, 3).SetValue("25.000đ"); // chữ
        ws.Cell(5, 4).Value = "Ly";
        ws.Cell(5, 5).Value = "Cà phê";
        ws.Cell(5, 6).SetValue("12.500");
        ws.Cell(6, 2).Value = "Bạc xỉu";
        ws.Cell(6, 3).Value = 30000; // số có định dạng tiền tệ
        ws.Cell(6, 3).Style.NumberFormat.Format = "#,##0 \"₫\"";
        ws.Cell(6, 7).SetValue("1.500");
        ws.Cell(7, 2).Value = "Trà đào";
        ws.Cell(7, 3).SetValue("35k");
        ws.Cell(8, 2).Value = "Tên món"; // tiêu đề lặp lại giữa bảng
        ws.Cell(8, 3).Value = "Đơn giá";

        var rows = PosProductExcelImportParser.ParseAll(Save(wb)).Products;

        Assert.Equal(["Cà phê sữa", "Bạc xỉu", "Trà đào"], rows.Select(r => r.Name));
        Assert.Equal([25000m, 30000m, 35000m], rows.Select(r => r.BasePrice));
        Assert.Equal("Ly", rows[0].BaseUnitName);
        Assert.Equal("Cà phê", rows[0].CategoryName);
        Assert.Equal(12500, rows[0].CostPrice);
        Assert.Equal(1500, rows[1].OnHandQty);
    }

    [Theory]
    [InlineData("Tên hàng")]
    [InlineData("Tên sản phẩm")]
    [InlineData("Mặt hàng")]
    [InlineData("Sản phẩm")]
    [InlineData("Món")]
    [InlineData("Product")]
    [InlineData("Item")]
    public void Parser_accepts_name_header_synonyms(string header)
    {
        using var wb = new XLWorkbook();
        var ws = wb.Worksheets.Add("A");
        ws.Cell(1, 1).Value = header;
        ws.Cell(1, 2).Value = "Giá bán";
        ws.Cell(2, 1).Value = "Phở bò";
        ws.Cell(2, 2).Value = 45000;
        var row = Assert.Single(PosProductExcelImportParser.ParseAll(Save(wb)).Products);
        Assert.Equal("Phở bò", row.Name);
        Assert.Equal(45000, row.BasePrice);
    }

    [Fact]
    public void Parser_handles_merged_header_cells()
    {
        using var wb = new XLWorkbook();
        var ws = wb.Worksheets.Add("A");
        ws.Cell(2, 1).Value = "Tên sản phẩm";
        ws.Range(2, 1, 3, 1).Merge(); // tiêu đề gộp 2 dòng
        ws.Cell(2, 2).Value = "Giá";
        ws.Range(2, 2, 2, 3).Merge(); // tiêu đề gộp 2 cột
        ws.Cell(3, 2).Value = "Lẻ";
        ws.Cell(4, 1).Value = "Bánh mì";
        ws.Cell(4, 2).Value = 20000;
        var row = Assert.Single(PosProductExcelImportParser.ParseAll(Save(wb)).Products);
        Assert.Equal("Bánh mì", row.Name);
        Assert.Equal(20000, row.BasePrice);
    }

    [Fact]
    public void Parser_reads_csv_and_rejects_xls()
    {
        var csv = Encoding.UTF8.GetBytes("Tên món;Giá bán;Đơn vị\nCà phê đen;\"25.000\";Ly\nNước cam;30k;Ly\n");
        var rows = PosProductExcelImportParser.ParseAll(csv, "menu.csv").Products;
        Assert.Equal([25000m, 30000m], rows.Select(r => r.BasePrice));
        Assert.True(PosProductExcelImportParser.IsLegacyXls([0xD0, 0xCF, 0x11, 0xE0, 0, 0, 0, 0], "a.xlsx"));
        Assert.True(PosProductExcelImportParser.IsLegacyXls([0x50, 0x4B, 3, 4], "old.XLS"));
        Assert.False(PosProductExcelImportParser.IsLegacyXls([0x50, 0x4B, 3, 4], "new.xlsx"));
    }

    [Theory]
    [InlineData("25.000", false, 25000)]
    [InlineData("25.000đ", true, 25000)]
    [InlineData("25,000 ₫", true, 25000)]
    [InlineData("1,5", false, 1.5)]
    [InlineData("10 cái", false, 10)]
    [InlineData("1tr2", true, 1200000)]
    [InlineData("-5", false, -5)]
    [InlineData("", false, 0)]
    public void ParseDec_reads_vietnamese_number_formats(string text, bool price, double expected) =>
        Assert.Equal((decimal)expected, PosProductExcelImportParser.ParseDec(text, price));

    static PosProductExcelImportParser.ImportRow Row(string name, string? code = null, string? barcode = null) =>
        new(code, barcode, name, null, null, null, 0, 1000, 0, 0, 0, "Cái",
            ZKTecoADMS.Domain.Enums.PosProductType.Goods, true, null, null, null, null);

    [Fact]
    public void MatchExisting_by_code_barcode_then_exact_name_only_without_codes()
    {
        var a = new object();
        var b = new object();
        var byCode = new Dictionary<string, object>(StringComparer.OrdinalIgnoreCase) { ["HH00001"] = a };
        var byBarcode = new Dictionary<string, object>(StringComparer.OrdinalIgnoreCase) { ["893"] = b };
        var byName = new Dictionary<string, object>
        {
            [PosProductNameMatch.ExactKey("Bánh mì bò")] = a,
            [PosProductNameMatch.ExactKey("Nước suối")] = b,
        };

        Assert.Same(a, PosProductExcelImportParser.MatchExisting(Row("x", code: "hh00001"), byCode, byBarcode, byName));
        Assert.Same(b, PosProductExcelImportParser.MatchExisting(Row("x", code: "HH9", barcode: "893"), byCode, byBarcode, byName));
        Assert.Same(a, PosProductExcelImportParser.MatchExisting(Row("  BÁNH MÌ  BÒ "), byCode, byBarcode, byName));
        Assert.Null(PosProductExcelImportParser.MatchExisting(Row("Bánh mì bơ"), byCode, byBarcode, byName)); // khác dấu
        Assert.Null(PosProductExcelImportParser.MatchExisting(Row("Bánh mì bò", code: "HH00099"), byCode, byBarcode, byName));
        Assert.Null(PosProductExcelImportParser.MatchExisting(Row("Nước suối", barcode: "999"), byCode, byBarcode, byName));
    }

    [Fact]
    public void ValidateRow_rejects_bad_rows_before_creating_entities()
    {
        Assert.Null(PosProductExcelImportParser.ValidateRow(Row("Cà phê")));
        Assert.NotNull(PosProductExcelImportParser.ValidateRow(Row(new string('x', 501))));
        Assert.NotNull(PosProductExcelImportParser.ValidateRow(Row("A", code: new string('1', 51))));
        Assert.NotNull(PosProductExcelImportParser.ValidateRow(Row("A") with { BasePrice = -1 }));
    }

    // ===== Bảng tính → TSV cho AI (mục 6) =====

    [Fact]
    public void SheetReader_xlsx_to_compact_tsv_fills_vertical_merges_and_keeps_numbers()
    {
        using var wb = new XLWorkbook();
        var ws = wb.Worksheets.Add("Bảng giá");
        ws.Cell(1, 1).Value = "Nhóm";
        ws.Cell(1, 2).Value = "Món";
        ws.Cell(1, 3).Value = "Giá";
        ws.Cell(2, 1).Value = "Cà phê";
        ws.Range(2, 1, 3, 1).Merge();
        ws.Cell(2, 2).Value = "Đen\t đá";
        ws.Cell(2, 3).Value = 25000;
        ws.Cell(2, 3).Style.NumberFormat.Format = "#,##0 \"₫\"";
        ws.Cell(3, 2).Value = "Sữa";
        ws.Cell(3, 3).Value = 29000;
        ws.Cell(5, 2).Value = "Ghi chú";
        var hidden = wb.Worksheets.Add("Ẩn");
        hidden.Cell(1, 1).Value = "bí mật";
        hidden.Hide();

        var sheets = PosMenuSheetReader.ReadXlsx(Save(wb));
        var (name, rows) = Assert.Single(sheets);
        Assert.Equal("Bảng giá", name);
        Assert.Equal(["Nhóm\tMón\tGiá", "Cà phê\tĐen đá\t25000", "Cà phê\tSữa\t29000", "\tGhi chú"], rows);
    }

    [Fact]
    public void SheetReader_csv_detects_delimiter_and_quotes()
    {
        var bytes = Encoding.UTF8.GetPreamble()
            .Concat(Encoding.UTF8.GetBytes("Tên,Giá\n\"Trà sữa, trân châu\",\"30,000\"\n\nBánh flan,15000\n"))
            .ToArray();
        var text = PosMenuSheetReader.Read(bytes, "hang.csv");
        var chunk = Assert.Single(text.Chunks);
        Assert.Equal(3, text.RowCount);
        Assert.Contains("Trà sữa, trân châu\t30,000\n", chunk.Text);
        Assert.Contains("Bánh flan\t15000\n", chunk.Text);
    }

    [Fact]
    public void SheetReader_rejects_too_large_and_xls()
    {
        var rows = Enumerable.Range(1, PosMenuSheetReader.MaxRows + 1).Select(i => $"Món {i}\t1000").ToList();
        var ex = Assert.Throws<InvalidOperationException>(() => PosMenuSheetReader.Build([("A", rows)]));
        Assert.Contains("Nhập Excel", ex.Message);

        var wide = Enumerable.Range(1, 100).Select(i => new string('x', 700)).ToList(); // ~70k ký tự
        Assert.Throws<InvalidOperationException>(() => PosMenuSheetReader.Build([("A", wide)]));

        var xls = Assert.Throws<InvalidOperationException>(() => PosMenuSheetReader.Read([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1], "menu.xls"));
        Assert.Equal(PosMenuSheetReader.XlsMessage, xls.Message);
    }

    [Fact]
    public void SheetReader_chunks_by_rows_and_chars_with_context_header()
    {
        var rows = new List<string> { "Tên\tGiá" };
        rows.AddRange(Enumerable.Range(1, 300).Select(i => $"Món {i}\t{i}000"));
        var text = PosMenuSheetReader.Build([("Menu", rows)]);
        Assert.Equal(3, text.Chunks.Count); // 120 + 120 + 61 dòng
        Assert.Equal((1, 120), (text.Chunks[0].FirstRow, text.Chunks[0].LastRow));
        Assert.DoesNotContain("chỉ để hiểu cột", text.Chunks[0].Text);
        Assert.Contains("Tên\tGiá\n", text.Chunks[2].Text);
        Assert.Contains("Món 300\t300000", text.Chunks[2].Text);

        var longRows = Enumerable.Range(1, 50).Select(i => $"Món {i}\t" + new string('a', 600)).ToList();
        var byChars = PosMenuSheetReader.Build([("B", longRows)]);
        Assert.True(byChars.Chunks.Count >= 3);
        Assert.All(byChars.Chunks, c => Assert.True(c.Text.Length < PosMenuSheetReader.ChunkChars + 3000));
    }
}

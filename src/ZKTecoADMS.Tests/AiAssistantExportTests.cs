using System.Text.Json.Nodes;
using ClosedXML.Excel;
using Xunit;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Application.DTOs.Permissions;

namespace ZKTecoADMS.Tests;

/// <summary>Xuất câu trả lời của trợ lý: bảng lấy từ JSON báo cáo, quyền Xuất, file Excel.</summary>
public class AiAssistantExportTests
{
    static readonly Dictionary<string, string> Period = new() { ["report"] = "pos_sales", ["from"] = "2026-10-01", ["to"] = "2026-10-31" };

    static AiReportRun Sales() => new("pos_sales", Period, JsonNode.Parse("""
        {
          "from": "2026-10-01T00:00:00.000", "to": "2026-10-31T00:00:00.000",
          "totalRevenue": 3413972846, "orderCount": 7148, "canViewAll": true, "storeId": "abc",
          "current": { "revenue": 100, "profit": 40 },
          "byDay": [
            { "date": "2026-10-01T00:00:00.000", "total": 1500000, "orderCount": 2, "note": "" },
            { "date": "2026-10-02T00:00:00.000", "total": 2500000.5, "orderCount": 3, "note": null }
          ],
          "byPayment": [],
          "topProducts": [ { "productId": "88c7", "productName": "=SUM(A1)", "qty": 2, "isActive": true, "lines": [ { "x": 1 } ] } ],
          "createdAtSample": "2026-10-30T07:55:47.482Z"
        }
        """));

    [Fact]
    public void Flatten_makes_overview_and_a_table_per_list()
    {
        var t = AiAssistantExport.Flatten(Sales());
        Assert.Equal(3, t.Count); // Tổng quan, Theo ngày, Top mặt hàng — danh sách rỗng bị bỏ

        var ov = t[0];
        Assert.Contains("Tổng quan", ov.Title);
        Assert.Equal("01/10/2026 – 31/10/2026", ov.Period);
        Assert.Contains(ov.Rows, r => (string)r[0]! == "Tổng doanh thu" && (decimal)r[1]! == 3413972846m);
        Assert.Contains(ov.Rows, r => (string)r[0]! == "Kỳ này · Doanh thu" && (decimal)r[1]! == 100m);
        // Khóa kỹ thuật, id không lọt vào file; ngày có Z đổi sang giờ VN.
        Assert.DoesNotContain(ov.Rows, r => ((string)r[0]!).Contains("Store", StringComparison.OrdinalIgnoreCase) || (string)r[0]! == "Can view all");
        Assert.Contains(ov.Rows, r => r[1] as string == "30/10/2026 14:55");

        var byDay = t[1];
        Assert.Equal(["Ngày", "Tổng", "Số đơn"], byDay.Columns); // cột «Ghi chú» trống cả bảng bị bỏ
        Assert.Equal("01/10/2026", byDay.Rows[0][0]);
        Assert.Equal(2500000.5m, byDay.Rows[1][1]);

        var top = t[2];
        Assert.Equal(["Tên hàng", "Số lượng", "Đang bán"], top.Columns); // id và danh sách lồng bị bỏ
        Assert.Equal("Có", top.Rows[0][2]);
    }

    [Fact]
    public void Status_values_become_vietnamese_and_unknown_keys_stay_readable()
    {
        Assert.Equal("Thu", AiAssistantExport.CellOf("type", JsonValue.Create("Income")!));
        Assert.Equal("Bánh mì", AiAssistantExport.CellOf("name", JsonValue.Create("Bánh mì")!));
        Assert.Null(AiAssistantExport.CellOf("name", JsonValue.Create(" ")!));
        Assert.Equal("Doanh thu", AiAssistantExport.LabelOf("revenue"));
        Assert.Equal("Brand new thing", AiAssistantExport.LabelOf("brandNewThing"));
    }

    [Fact]
    public void Root_list_and_long_list_are_handled()
    {
        var big = new JsonArray();
        for (var i = 0; i < AiAssistantExport.MaxRowsPerTable + 5; i++) big.Add(new JsonObject { ["qty"] = i });
        var t = Assert.Single(AiAssistantExport.Flatten(new AiReportRun("pos_goods", new Dictionary<string, string>(), big)));
        Assert.Equal(AiAssistantExport.MaxRowsPerTable, t.Rows.Count);
        Assert.True(t.Truncated);
    }

    [Fact]
    public void Same_report_with_same_args_is_exported_once()
    {
        var doc = AiAssistantExport.Build([Sales(), Sales()], "Nhận xét");
        Assert.Equal(3, doc.Tables.Count);
        Assert.Equal(AiAssistantReportCatalog.TitleOf("pos_sales"), doc.Title);
    }

    [Fact]
    public void Export_needs_the_export_permission_of_the_report()
    {
        var runs = new[] { Sales() };
        Dictionary<string, ModulePermissionDto> Perm(bool view, bool export) =>
            new() { ["PosSalesReport"] = new ModulePermissionDto { CanView = view, CanExport = export } };
        Assert.Empty(AiAssistantExport.Exportable(runs, Perm(true, false), false));
        Assert.Empty(AiAssistantExport.Exportable(runs, new Dictionary<string, ModulePermissionDto>(), false));
        Assert.Single(AiAssistantExport.Exportable(runs, Perm(true, true), false));
        Assert.Single(AiAssistantExport.Exportable(runs, new Dictionary<string, ModulePermissionDto>(), true));
    }

    [Fact]
    public void Excel_has_a_sheet_per_table_real_numbers_and_no_formula_from_data()
    {
        var bytes = AiAssistantExport.ToExcel(AiAssistantExport.Build([Sales()], "Doanh thu tăng.\nNên nhập thêm hàng."), null);
        using var wb = new XLWorkbook(new MemoryStream(bytes));
        Assert.Equal(4, wb.Worksheets.Count);
        Assert.Contains(wb.Worksheets, w => w.Name.StartsWith("Nhận xét", StringComparison.Ordinal));

        var day = wb.Worksheets.First(w => w.Name.Contains("Theo ngày"));
        var total = day.CellsUsed().First(c => c.GetString() == "Tổng");
        Assert.Equal(1500000d, day.Cell(total.Address.RowNumber + 1, total.Address.ColumnNumber).GetDouble());

        // Tên hàng do người dùng đặt không được chạy thành công thức khi mở file.
        var top = wb.Worksheets.First(w => w.Name.Contains("Top"));
        var cell = top.CellsUsed().First(c => c.GetString() == "=SUM(A1)");
        Assert.False(cell.HasFormula);
    }

    [Fact]
    public void Sheet_names_are_valid_and_unique()
    {
        var used = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var a = AiAssistantExport.SheetName("Doanh thu chi tiết rất rất dài của cửa hàng – Theo ngày", used);
        var b = AiAssistantExport.SheetName("Báo cáo khác cũng rất rất dài của cửa hàng – Theo ngày", used);
        var c = AiAssistantExport.SheetName("Thu/chi: [tháng]?", used);
        Assert.Equal("Theo ngày", a);
        Assert.Equal("Theo ngày (2)", b);
        Assert.DoesNotContain(c, x => ":\\/?*[]".Contains(x));
        Assert.All(new[] { a, b, c }, n => Assert.True(n.Length <= 31));
    }

    [Theory]
    [InlineData("xuất excel doanh thu tháng này")]
    [InlineData("xuat file pdf ton kho")]
    [InlineData("xuất ra ảnh hàng bán chạy")]
    public void Export_requests_go_to_the_agent(string q) => Assert.True(AiAssistantAgent.LooksAnalytical(q));
}

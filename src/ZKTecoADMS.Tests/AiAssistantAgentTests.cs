using System.Text.Json.Nodes;
using Xunit;
using ZKTecoADMS.Api.Middlewares;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Application.DTOs.Permissions;

namespace ZKTecoADMS.Tests;

/// <summary>Trợ lý ảo phân tích: danh mục báo cáo, lọc quyền, thu gọn số liệu.</summary>
public class AiAssistantAgentTests
{
    static Dictionary<string, ModulePermissionDto> Perms(params string[] viewable) =>
        viewable.ToDictionary(m => m, m => new ModulePermissionDto { Module = m, CanView = true });

    [Fact]
    public void Bao_cao_POS_tro_dung_chuc_nang_goi_cua_API()
    {
        // Lọc theo gói ở trợ lý phải khớp chức năng middleware kiểm khi gọi API thật.
        foreach (var r in AiAssistantReportCatalog.All.Where(r => r.Line == "pos"))
        {
            var module = StorePackageModuleMiddleware.ResolveModule(r.Path);
            Assert.True(module != null && r.Modules.Contains(module), $"{r.Id}: {r.Path} → {module}");
        }
    }

    [Fact]
    public void Thu_ngan_khong_thay_bao_cao_loi_nhuan_va_luong()
    {
        var cashier = AiAssistantReportCatalog.Allowed(Perms("PosSell", "PosSalesReport", "PosReportEndOfDay"), false, null)
            .Select(r => r.Id).ToList();
        Assert.Contains("pos_overview", cashier);
        Assert.Contains("pos_staff_sales", cashier);
        Assert.DoesNotContain("pos_profit_products", cashier);
        Assert.DoesNotContain("hr_payroll", cashier);

        // Gói không có chức năng → không hiện dù vai trò toàn quyền.
        var owner = AiAssistantReportCatalog.Allowed(Perms(), true, ["PosSell", "PosSalesReport"]).Select(r => r.Id).ToList();
        Assert.Contains("pos_sales", owner);
        Assert.DoesNotContain("hr_attendance_monthly", owner);
    }

    [Fact]
    public void Tham_so_chung_doi_dung_ten_tham_so_API()
    {
        var late = AiAssistantReportCatalog.Find("hr_late_early")!;
        var q = AiAssistantReportCatalog.BuildQuery(late, new Dictionary<string, string>
        {
            ["from"] = "2026-10-01", ["to"] = "2026-10-05", ["limit"] = "5", ["report"] = "hr_late_early",
        });
        Assert.Equal("?startDate=2026-10-01&endDate=2026-10-05", q);

        var stock = AiAssistantReportCatalog.Find("pos_stock_products")!;
        Assert.Equal("?filter=BelowMin&pageSize=50",
            AiAssistantReportCatalog.BuildQuery(stock, new Dictionary<string, string> { ["mode"] = "BelowMin" }));
    }

    [Fact]
    public void Thu_gon_so_lieu_cat_mang_dai_va_bo_id()
    {
        var rows = new JsonArray();
        for (var i = 0; i < 300; i++)
            rows.Add(new JsonObject { ["productId"] = Guid.NewGuid().ToString(), ["name"] = $"Món {i}", ["revenue"] = i * 1000, ["note"] = null });
        var data = new JsonObject { ["totalRevenue"] = 123, ["items"] = rows };

        var c = AiAssistantAgent.Compact(data, maxChars: 3000)!;
        Assert.True(c.ToJsonString().Length <= 3000);
        Assert.Equal(123, (int)c["totalRevenue"]!);
        var items = c["items"]!.AsArray();
        Assert.Contains("còn", items[^1]!.ToString());
        Assert.Null(items[0]!["productId"]);
        Assert.Equal("Món 0", (string)items[0]!["name"]!);
    }

    [Theory]
    [InlineData("gemini-flash-latest", "gemini-flash-latest")]
    [InlineData("gemini-flash-lite-latest", "gemini-flash-lite-latest")]
    [InlineData("gemini-2.5-flash", "gemini-flash-latest")]
    [InlineData("gemini-pro-latest", "gemini-flash-latest")]
    [InlineData(null, "gemini-flash-latest")]
    public void Model_cu_tu_ve_Flash_moi_nhat(string? saved, string expected) =>
        Assert.Equal(expected, GeminiModels.Normalize(saved));

    [Fact]
    public void Doi_markdown_thanh_chu_thuong()
    {
        var md = "### 1. Tổng quan\n* **Doanh thu:** 7.043.408đ\n  - Tiền mặt\n---\n\n\n**Gợi ý**";
        Assert.Equal("1. Tổng quan\n• Doanh thu: 7.043.408đ\n  • Tiền mặt\n\nGợi ý",
            AiAssistantAgent.PlainText(md).Replace("\r", ""));
    }

    [Theory]
    [InlineData("Doanh thu tháng này so với tháng trước thế nào?", true)]
    [InlineData("phân tích tình hình đi trễ của nhân viên", true)]
    [InlineData("Món nào bán chậm nhất tuần này", true)]
    [InlineData("Tôi còn bao nhiêu ngày phép", false)]
    [InlineData("hôm nay tôi chấm công chưa", false)]
    public void Nhan_dang_cau_hoi_phan_tich(string q, bool expected) =>
        Assert.Equal(expected, AiAssistantAgent.LooksAnalytical(q));
}

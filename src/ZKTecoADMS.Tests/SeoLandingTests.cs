using ClosedXML.Excel;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Xunit;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Api.Seo;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Tests;

/// <summary>Trang đích SEO: tính năng (/tinh-nang), bảng giá, tài liệu tải về + form thu SĐT, FAQ → FAQPage.</summary>
public class SeoLandingTests
{
    static SeoArticle Page(string site, string slug, string title, string type = "article", string? cat = null) => new()
    {
        Id = Guid.NewGuid(), Site = site, Slug = slug, Title = title, PageType = type, Category = cat, IsPublished = true,
        PublishedAt = DateTime.UtcNow.AddDays(-1), Summary = "Tóm tắt trang.", MetaDescription = "Mô tả cho Google.",
        ContentMarkdown = "## Mục một\n\nNội dung.\n\n## Mục hai\n\nThêm.\n\n## Câu hỏi thường gặp\n\n### Có dùng thử không\nCó, miễn phí.\n\n### Có xuất Excel không?\nĐược.",
    };

    static ZKTecoDbContext Db() => new(new DbContextOptionsBuilder<ZKTecoDbContext>()
        .UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);

    static PublicSeoController Ctl(ZKTecoDbContext db, string host)
    {
        var http = new DefaultHttpContext();
        http.Request.Host = new HostString(host);
        return new PublicSeoController(db) { ControllerContext = new ControllerContext { HttpContext = http } };
    }

    [Fact]
    public void Faq_section_becomes_question_answer_pairs()
    {
        var faq = SeoPages.Faq(Page("hrm", "a", "A").ContentMarkdown);
        Assert.Equal(2, faq.Count);
        Assert.Equal("Có dùng thử không?", faq[0].Question);
        Assert.Equal("Có, miễn phí.", faq[0].Answer);
        Assert.Equal("Có xuất Excel không?", faq[1].Question);
        Assert.Empty(SeoPages.Faq("## Mục\n\n### Không phải FAQ\nNội dung."));
    }

    [Fact]
    public void Seed_features_and_articles_cover_both_sites_with_faq()
    {
        var asm = typeof(SeoArticleSeeder).Assembly;
        var seeds = asm.GetManifestResourceNames().Where(n => n.StartsWith("Sbox.SeoSeed."))
            .Select(n =>
            {
                using var r = new StreamReader(asm.GetManifestResourceStream(n)!);
                return SeoArticleSeeder.Parse(r.ReadToEnd())!;
            }).ToList();
        Assert.True(seeds.Count(s => s.Site == "hrm" && s.PageType == "feature") >= 6);
        Assert.True(seeds.Count(s => s.Site == "pos" && s.PageType == "feature") >= 6);
        Assert.True(seeds.Count(s => s.PageType == "article") >= 25);
        Assert.All(seeds.Where(s => s.PageType == "feature"), s => Assert.True(SeoPages.Faq(s.Body).Count >= 3, s.Slug));
        // Không trùng slug trong cùng site
        Assert.Equal(seeds.Count, seeds.Select(s => (s.Site, s.Slug)).Distinct().Count());
        // FAQ không bị lẫn ghi chú cuối bài
        Assert.All(seeds.SelectMany(s => SeoPages.Faq(s.Body)), f => Assert.DoesNotContain("Bài viết mang tính tham khảo", f.Answer));
    }

    [Fact]
    public void Feature_page_has_single_h1_faq_and_lead_form()
    {
        var f = Page("hrm", "phan-mem-tinh-luong", "Phần mềm tính lương", "feature", "Tính lương");
        var html = SeoPages.FeaturePage(SeoPages.Hrm, f, [Page("hrm", "xep-ca", "Xếp ca", "feature")], [Page("hrm", "bai", "Bài viết A")]);
        Assert.Contains("<link rel=\"canonical\" href=\"https://sboxhrm.com/tinh-nang/phan-mem-tinh-luong\">", html);
        Assert.Equal(1, html.Split("<h1>").Length - 1);
        Assert.Contains("\"@type\":\"FAQPage\"", html);
        Assert.Contains("\"@type\":\"SoftwareApplication\"", html);
        Assert.Contains("/api/public/leads", html);
        Assert.Contains("/tinh-nang/xep-ca", html);
        Assert.Contains("/bai-viet/bai", html);
        Assert.DoesNotContain("sboxpos.com", html);
    }

    [Fact]
    public void Pricing_page_lists_plans_and_contact_price()
    {
        var plans = new List<SeoPages.PricingPlan>
        {
            new("Gói A", "Mô tả A", 99000, 990000, 30, 10, 2, 1, null, true, ["Ý nổi bật"], [("Chấm công", ["Chấm công Mobile"])]),
            new("Gói B", null, null, null, 0, 0, 0, 0, "Mới", false, [], []),
        };
        var html = SeoPages.PricingPage(SeoPages.Pos, plans);
        Assert.Contains("99.000 đ", html);
        Assert.Contains("Dùng thử miễn phí 30 ngày", html);
        Assert.Contains("Liên hệ báo giá", html);
        Assert.Contains("\"@type\":\"FAQPage\"", html);
        Assert.Contains("\"price\":\"99000\"", html);
        Assert.Contains("https://sboxpos.com/bang-gia", html);
    }

    [Fact]
    public void Resource_workbooks_build_with_working_formulas()
    {
        foreach (var r in SeoResources.All)
        {
            using var wb = r.Build();
            using var ms = new MemoryStream();
            wb.SaveAs(ms);
            Assert.True(ms.Length > 3000, r.Slug);
        }

        using var payroll = SeoResources.Find("hrm", "mau-bang-luong-excel-2026")!.Build();
        var ws = payroll.Worksheet("Bảng lương");
        // NV001: 9.000.000 / 26 × 24 công
        Assert.Equal(8_307_692d, ws.Cell("L5").GetDouble());
        // NV003: lương 25tr, đóng BH 20tr, 2 người phụ thuộc → thuế dương, thực lĩnh < tổng thu nhập
        Assert.True(ws.Cell("U7").GetDouble() >= 0);
        Assert.True(ws.Cell("V7").GetDouble() < ws.Cell("N7").GetDouble());

        using var stock = SeoResources.Find("pos", "mau-quan-ly-kho-nhap-xuat-ton")!.Build();
        var inv = stock.Worksheet("Tồn kho");
        Assert.Equal(26d, inv.Cell("F5").GetDouble()); // 20 tồn đầu + 10 nhập − 4 xuất
    }

    [Fact]
    public async Task Feature_routes_redirect_by_type_and_pages_render()
    {
        var db = Db();
        db.AddRange(Page("pos", "goi-mon-qr", "Gọi món QR", "feature"), Page("pos", "kinh-nghiem", "Kinh nghiệm"),
            Page("hrm", "tinh-luong", "Tính lương", "feature"));
        db.ServicePackages.Add(new ServicePackage { Id = Guid.NewGuid(), Name = "POS Cơ bản", ProductLine = "pos", IsActive = true, IsPublic = true });
        db.ServicePackages.Add(new ServicePackage { Id = Guid.NewGuid(), Name = "Gói ẩn", ProductLine = "pos", IsActive = true, IsPublic = false });
        await db.SaveChangesAsync();

        var list = Assert.IsType<ContentResult>(await Ctl(db, "sboxpos.com").FeatureList());
        Assert.Contains("Gọi món QR", list.Content);
        Assert.DoesNotContain("Tính lương", list.Content);
        Assert.DoesNotContain("Kinh nghiệm", list.Content);

        Assert.Equal(200, Assert.IsType<ContentResult>(await Ctl(db, "sboxpos.com").Feature("goi-mon-qr")).StatusCode);
        Assert.Equal("/bai-viet/kinh-nghiem", Assert.IsType<RedirectResult>(await Ctl(db, "sboxpos.com").Feature("kinh-nghiem")).Url);
        Assert.Equal("/tinh-nang/goi-mon-qr", Assert.IsType<RedirectResult>(await Ctl(db, "sboxpos.com").Article("goi-mon-qr")).Url);

        // Danh sách bài viết không lẫn trang tính năng
        var posts = Assert.IsType<ContentResult>(await Ctl(db, "sboxpos.com").List(null));
        Assert.DoesNotContain("Gọi món QR", posts.Content);

        var pricing = Assert.IsType<ContentResult>(await Ctl(db, "sboxpos.com").Pricing());
        Assert.Contains("POS Cơ bản", pricing.Content);
        Assert.DoesNotContain("Gói ẩn", pricing.Content);

        var sitemap = Assert.IsType<ContentResult>(await Ctl(db, "sboxpos.com").Sitemap());
        Assert.Contains("https://sboxpos.com/tinh-nang/goi-mon-qr", sitemap.Content);
        Assert.Contains("https://sboxpos.com/bai-viet/kinh-nghiem", sitemap.Content);
        Assert.Contains("https://sboxpos.com/bang-gia", sitemap.Content);

        var res = Assert.IsType<ContentResult>(Ctl(db, "sboxhrm.com").Resources());
        Assert.Contains("Mẫu bảng lương Excel 2026", res.Content);
        Assert.DoesNotContain("quản lý kho", res.Content);
    }

    [Fact]
    public async Task Resource_lead_saves_contact_and_returns_download_link()
    {
        var db = Db();
        var ctl = Ctl(db, "sboxhrm.com");
        var dto = new PublicSeoController.LeadDto("Nguyễn An", "0905 123 456", "Cty A", null, null, null);

        var ok = Assert.IsType<OkObjectResult>(await ctl.ResourceLead("mau-bang-luong-excel-2026", dto));
        Assert.Contains("/tai-lieu/tai/mau-bang-luong-excel-2026", System.Text.Json.JsonSerializer.Serialize(ok.Value));
        var lead = Assert.Single(db.ConsultationRequests);
        Assert.Equal("TaiLieu", lead.Source);
        Assert.Equal("0905123456", lead.NormalizedPhone);

        // Gửi lại ngay: không ghi trùng, vẫn trả liên kết
        Assert.IsType<OkObjectResult>(await ctl.ResourceLead("mau-bang-luong-excel-2026", dto));
        Assert.Single(db.ConsultationRequests);

        Assert.IsType<BadRequestObjectResult>(await ctl.ResourceLead("mau-bang-luong-excel-2026", dto with { Phone = "12" }));
        Assert.IsType<BadRequestObjectResult>(await ctl.ResourceLead("mau-bang-luong-excel-2026", dto with { Website = "bot" }));
        Assert.IsType<NotFoundObjectResult>(await ctl.ResourceLead("khong-co", dto));

        var file = Assert.IsType<FileContentResult>(ctl.Download("mau-bang-luong-excel-2026"));
        Assert.Equal("mau-bang-luong-2026.xlsx", file.FileDownloadName);
    }

    [Fact]
    public void Local_pages_cover_34_provinces_with_unique_content()
    {
        Assert.Equal(34, SeoPages.Provinces.Count);
        Assert.Equal(34, SeoPages.Provinces.Select(p => p.Slug).Distinct().Count());
        Assert.Equal(34, SeoPages.Provinces.Select(p => p.Profile).Distinct().Count());
        // 23 tỉnh/thành hình thành từ sáp nhập, 11 giữ nguyên
        Assert.Equal(23, SeoPages.Provinces.Count(p => p.Old.Length > 0));
        foreach (var p in SeoPages.Provinces)
        {
            Assert.Equal(p.Slug, SeoMarkdown.Slugify(p.Slug));
            var html = SeoPages.LocalPage(p);
            Assert.Equal(1, html.Split("<h1>").Length - 1);
            Assert.Contains($"https://sboxhrm.com/lap-dat-may-cham-cong/{p.Slug}", html);
            Assert.Contains("\"@type\":\"FAQPage\"", html);
            Assert.Contains("\"@type\":\"Service\"", html);
            Assert.Contains("miễn phí lắp đặt", html);
            Assert.DoesNotContain("nhà phân phối chính hãng", html);
            foreach (var o in p.Old) Assert.Contains(o, html);
            var title = System.Text.RegularExpressions.Regex.Match(html, "<title>(.*?)</title>").Groups[1].Value;
            Assert.InRange(title.Length, 30, 70);
            var desc = System.Text.RegularExpressions.Regex.Match(html, "name=\"description\" content=\"(.*?)\"").Groups[1].Value;
            Assert.InRange(desc.Length, 100, 170);
        }
        var hub = SeoPages.LocalHubPage();
        Assert.Equal(34, System.Text.RegularExpressions.Regex.Matches(hub, "href=\"/lap-dat-may-cham-cong/[a-z0-9-]+\"").Count);
    }

    [Fact]
    public async Task Local_routes_only_on_hrm_and_in_sitemap()
    {
        var db = Db();
        Assert.Equal(200, Assert.IsType<ContentResult>(Ctl(db, "sboxhrm.com").Local("da-nang")).StatusCode);
        Assert.Equal(404, Assert.IsType<ContentResult>(Ctl(db, "sboxhrm.com").Local("khong-co")).StatusCode);
        Assert.Equal("https://sboxhrm.com/lap-dat-may-cham-cong/da-nang",
            Assert.IsType<RedirectResult>(Ctl(db, "sboxpos.com").Local("da-nang")).Url);
        var hrm = Assert.IsType<ContentResult>(await Ctl(db, "sboxhrm.com").Sitemap());
        Assert.Contains("https://sboxhrm.com/lap-dat-may-cham-cong/ho-chi-minh", hrm.Content);
        var pos = Assert.IsType<ContentResult>(await Ctl(db, "sboxpos.com").Sitemap());
        Assert.DoesNotContain("lap-dat-may-cham-cong", pos.Content);
    }
}

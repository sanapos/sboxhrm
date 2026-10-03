using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Xunit;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Api.Seo;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Tests;

/// <summary>Bài viết SEO: Markdown an toàn, bài mẫu đọc được, HTML phía server đúng tên miền, sitemap theo site.</summary>
public class SeoArticleTests
{
    [Fact]
    public void Markdown_escapes_html_and_blocks_unsafe_links()
    {
        var html = SeoMarkdown.ToHtml("## Tiêu đề <script>\n\nĐoạn <b>x</b> [hay](javascript:alert(1)) và [tốt](/register) **đậm**\n\n- a\n- b\n\n| A | B |\n|---|---|\n| 1 | 2 |");
        Assert.DoesNotContain("<script>", html);
        Assert.DoesNotContain("<b>", html);
        Assert.DoesNotContain("javascript:", html);
        Assert.Contains("<h2 id=\"tieu-de-script\">", html);
        Assert.Contains("<a href=\"/register\">tốt</a>", html);
        Assert.Contains("<strong>đậm</strong>", html);
        Assert.Contains("<ul>", html);
        Assert.Contains("<table>", html);
        Assert.Equal("cach-tinh-luong-theo-ngay-cong", SeoMarkdown.Slugify("Cách tính lương theo ngày công"));
        Assert.Equal("dang-ky-dung-thu", SeoMarkdown.Slugify("Đăng ký — dùng thử!"));
    }

    [Fact]
    public void All_embedded_seed_articles_parse()
    {
        var asm = typeof(SeoArticleSeeder).Assembly;
        var names = asm.GetManifestResourceNames().Where(n => n.StartsWith("Sbox.SeoSeed.")).ToList();
        Assert.True(names.Count >= 6);
        foreach (var n in names)
        {
            using var r = new StreamReader(asm.GetManifestResourceStream(n)!);
            var a = SeoArticleSeeder.Parse(r.ReadToEnd());
            Assert.NotNull(a);
            Assert.Equal(a!.Slug, SeoMarkdown.Slugify(a.Slug));
            Assert.InRange(a.MetaDescription!.Length, 100, 200);
            Assert.True(SeoMarkdown.PlainText(a.Body).Split(' ').Length > 500, n + " quá ngắn");
            Assert.Contains("](/register)", a.Body);
        }
        Assert.Contains(names, n => n.Contains("hrm-"));
        Assert.Contains(names, n => n.Contains("pos-"));
    }

    static SeoArticle Art(string site, string slug, string title, string? cat = null) => new()
    {
        Id = Guid.NewGuid(), Site = site, Slug = slug, Title = title, Category = cat, IsPublished = true,
        PublishedAt = DateTime.UtcNow.AddDays(-1), ContentMarkdown = "## Mục một\n\nNội dung.\n\n## Mục hai\n\nThêm.",
        MetaDescription = "Mô tả bài viết dùng cho Google.",
    };

    [Fact]
    public void Article_page_has_domain_canonical_and_structured_data()
    {
        var a = Art("hrm", "cach-tinh-luong", "Cách tính lương", "Tính lương");
        var html = SeoPages.ArticlePage(SeoPages.Hrm, a, [Art("hrm", "khac", "Bài khác")]);
        Assert.Contains("<link rel=\"canonical\" href=\"https://sboxhrm.com/bai-viet/cach-tinh-luong\">", html);
        Assert.Contains("\"@type\":\"BlogPosting\"", html);
        Assert.Contains("\"@type\":\"BreadcrumbList\"", html);
        Assert.Contains("<h1>Cách tính lương</h1>", html);
        Assert.Contains("Nội dung bài viết", html); // mục lục khi có ≥ 2 mục
        Assert.Contains("/bai-viet/khac", html);
        Assert.DoesNotContain("sboxpos.com", html);
        Assert.Equal(1, html.Split("<h1>").Length - 1);
    }

    [Fact]
    public async Task Public_pages_follow_host_and_hide_drafts()
    {
        var db = new ZKTecoDbContext(new DbContextOptionsBuilder<ZKTecoDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);
        var draft = Art("pos", "nhap", "Bản nháp");
        draft.IsPublished = false;
        db.AddRange(Art("hrm", "bai-hrm", "Bài HRM"), Art("pos", "bai-pos", "Bài POS", "Kinh nghiệm"), draft);
        await db.SaveChangesAsync();

        PublicSeoController Ctl(string host)
        {
            var http = new DefaultHttpContext();
            http.Request.Host = new HostString(host);
            return new PublicSeoController(db) { ControllerContext = new ControllerContext { HttpContext = http } };
        }

        var pos = Assert.IsType<ContentResult>(await Ctl("sboxpos.com").List(null));
        Assert.Contains("Bài POS", pos.Content);
        Assert.DoesNotContain("Bài HRM", pos.Content);
        Assert.DoesNotContain("Bản nháp", pos.Content);

        var article = Assert.IsType<ContentResult>(await Ctl("sboxpos.com").Article("bai-pos"));
        Assert.Equal(200, article.StatusCode);
        Assert.Contains("https://sboxpos.com/bai-viet/bai-pos", article.Content);

        // Bài HRM không mở được trên sboxpos.com; bản nháp 404
        Assert.Equal(404, Assert.IsType<ContentResult>(await Ctl("sboxpos.com").Article("bai-hrm")).StatusCode);
        Assert.Equal(404, Assert.IsType<ContentResult>(await Ctl("sboxpos.com").Article("nhap")).StatusCode);

        var sitemap = Assert.IsType<ContentResult>(await Ctl("sboxhrm.com").Sitemap());
        Assert.Contains("https://sboxhrm.com/bai-viet/bai-hrm", sitemap.Content);
        Assert.DoesNotContain("bai-pos", sitemap.Content);

        var robots = Assert.IsType<ContentResult>(Ctl("sboxpos.com").Robots());
        Assert.Contains("Sitemap: https://sboxpos.com/sitemap.xml", robots.Content);
    }
}

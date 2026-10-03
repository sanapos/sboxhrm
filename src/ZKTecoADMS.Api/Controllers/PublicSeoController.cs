using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Seo;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// Trang bài viết SEO công khai, dựng HTML phía server theo tên miền (sboxhrm.com / sboxpos.com):
/// /bai-viet, /bai-viet/{slug}, /seo/sitemap.xml, /seo/robots.txt (nginx trỏ /sitemap.xml, /robots.txt vào đây),
/// /api/public/articles (khối «Bài viết mới» trên trang chủ).
/// </summary>
[ApiController]
[AllowAnonymous]
public class PublicSeoController(ZKTecoDbContext db) : ControllerBase
{
    const int PageSize = 12;

    SeoPages.SiteInfo Site => SeoPages.Detect(
        Request.Headers["X-Forwarded-Host"].FirstOrDefault() ?? Request.Host.Host,
        Request.Query["site"].FirstOrDefault());

    IQueryable<SeoArticle> Published(string site) =>
        db.Set<SeoArticle>().AsNoTracking().Where(a => a.Site == site && a.IsPublished && a.Deleted == null
            && (a.PublishedAt == null || a.PublishedAt <= DateTime.UtcNow));

    ContentResult Html(string html, int status = 200, int cacheSeconds = 300)
    {
        Response.Headers.CacheControl = $"public, max-age={cacheSeconds}";
        return new ContentResult { Content = html, ContentType = "text/html; charset=utf-8", StatusCode = status };
    }

    [HttpGet("/bai-viet")]
    public async Task<IActionResult> List([FromQuery(Name = "chuyen-muc")] string? category, [FromQuery(Name = "trang")] int page = 1, CancellationToken ct = default)
    {
        var s = Site;
        var q = Published(s.Code);
        var categories = await q.Where(a => a.Category != null && a.Category != "")
            .Select(a => a.Category!).Distinct().OrderBy(c => c).ToListAsync(ct);
        if (!string.IsNullOrWhiteSpace(category))
        {
            category = category.Trim();
            if (!categories.Contains(category)) category = null;
            else q = q.Where(a => a.Category == category);
        }
        var total = await q.CountAsync(ct);
        var totalPages = Math.Max(1, (int)Math.Ceiling(total / (double)PageSize));
        page = Math.Clamp(page, 1, totalPages);
        var items = await q.OrderByDescending(a => a.SortOrder).ThenByDescending(a => a.PublishedAt ?? a.CreatedAt)
            .Skip((page - 1) * PageSize).Take(PageSize).ToListAsync(ct);
        return Html(SeoPages.ListPage(s, items, page, totalPages, category, categories));
    }

    [HttpGet("/bai-viet/{slug}")]
    public async Task<IActionResult> Article(string slug, CancellationToken ct = default)
    {
        var s = Site;
        var key = (slug ?? "").Trim().ToLowerInvariant();
        var a = await Published(s.Code).FirstOrDefaultAsync(x => x.Slug == key, ct);
        if (a == null) return Html(SeoPages.NotFoundPage(s), 404, 60);

        // Bài cùng chuyên mục trước, rồi bài mới nhất.
        var related = await Published(s.Code).Where(x => x.Id != a.Id)
            .OrderByDescending(x => x.Category == a.Category)
            .ThenByDescending(x => x.PublishedAt ?? x.CreatedAt)
            .Take(5).ToListAsync(ct);

        try
        {
            await db.Set<SeoArticle>().Where(x => x.Id == a.Id)
                .ExecuteUpdateAsync(u => u.SetProperty(x => x.ViewCount, x => x.ViewCount + 1), ct);
        }
        catch { /* đếm lượt xem không được làm hỏng trang */ }

        return Html(SeoPages.ArticlePage(s, a, related));
    }

    [HttpGet("/seo/sitemap.xml")]
    public async Task<IActionResult> Sitemap(CancellationToken ct = default)
    {
        var s = Site;
        var items = await Published(s.Code).OrderByDescending(a => a.PublishedAt ?? a.CreatedAt).Take(5000).ToListAsync(ct);
        Response.Headers.CacheControl = "public, max-age=900";
        return Content(SeoPages.Sitemap(s, items), "application/xml; charset=utf-8");
    }

    [HttpGet("/seo/robots.txt")]
    public IActionResult Robots()
    {
        Response.Headers.CacheControl = "public, max-age=3600";
        return Content(SeoPages.Robots(Site), "text/plain; charset=utf-8");
    }

    /// <summary>Bài viết mới cho trang chủ (JSON).</summary>
    [HttpGet("/api/public/articles")]
    public async Task<IActionResult> Latest([FromQuery] int take = 6, CancellationToken ct = default)
    {
        var s = Site;
        take = Math.Clamp(take, 1, 12);
        var items = await Published(s.Code).OrderByDescending(a => a.SortOrder).ThenByDescending(a => a.PublishedAt ?? a.CreatedAt)
            .Take(take).ToListAsync(ct);
        Response.Headers.CacheControl = "public, max-age=300";
        return Ok(new
        {
            isSuccess = true,
            data = items.Select(a => new
            {
                a.Slug,
                a.Title,
                description = SeoPages.Description(a),
                a.Category,
                coverImageUrl = string.IsNullOrWhiteSpace(a.CoverImageUrl) ? s.DefaultImage : a.CoverImageUrl,
                publishedAt = a.PublishedAt ?? a.CreatedAt,
                url = "/bai-viet/" + a.Slug,
            }),
        });
    }
}

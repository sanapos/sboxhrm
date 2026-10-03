using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;
using System.Text.RegularExpressions;
using ZKTecoADMS.Application.Authorization;
using ZKTecoADMS.Api.Seo;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// Trang bài viết SEO công khai, dựng HTML phía server theo tên miền (sboxhrm.com / sboxpos.com):
/// /bai-viet, /bai-viet/{slug}, /seo/sitemap.xml, /seo/robots.txt (nginx trỏ /sitemap.xml, /robots.txt vào đây),
/// /api/public/articles (khối «Bài viết mới» trên trang chủ); /tinh-nang, /tinh-nang/{slug} (trang giải pháp),
/// /bang-gia, /tai-lieu (tài liệu Excel tải miễn phí, đổi lấy SĐT → ConsultationRequests).
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

    IQueryable<SeoArticle> Posts(string site) => Published(site).Where(a => a.PageType != "feature");
    IQueryable<SeoArticle> Features(string site) => Published(site).Where(a => a.PageType == "feature");

    ContentResult Html(string html, int status = 200, int cacheSeconds = 300)
    {
        Response.Headers.CacheControl = $"public, max-age={cacheSeconds}";
        return new ContentResult { Content = html, ContentType = "text/html; charset=utf-8", StatusCode = status };
    }

    [HttpGet("/bai-viet")]
    public async Task<IActionResult> List([FromQuery(Name = "chuyen-muc")] string? category, [FromQuery(Name = "trang")] int page = 1, CancellationToken ct = default)
    {
        var s = Site;
        var q = Posts(s.Code);
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
        if (a.PageType == "feature") return RedirectPermanent("/tinh-nang/" + a.Slug);

        // Bài cùng chuyên mục trước, rồi bài mới nhất.
        var related = await Posts(s.Code).Where(x => x.Id != a.Id)
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

    [HttpGet("/tinh-nang")]
    public async Task<IActionResult> FeatureList(CancellationToken ct = default)
    {
        var s = Site;
        var items = await Features(s.Code).OrderByDescending(a => a.SortOrder).ThenBy(a => a.Title).ToListAsync(ct);
        return Html(SeoPages.FeatureIndexPage(s, items));
    }

    [HttpGet("/tinh-nang/{slug}")]
    public async Task<IActionResult> Feature(string slug, CancellationToken ct = default)
    {
        var s = Site;
        var key = (slug ?? "").Trim().ToLowerInvariant();
        var a = await Published(s.Code).FirstOrDefaultAsync(x => x.Slug == key, ct);
        if (a == null) return Html(SeoPages.NotFoundPage(s), 404, 60);
        if (a.PageType != "feature") return RedirectPermanent("/bai-viet/" + a.Slug);
        var others = await Features(s.Code).Where(x => x.Id != a.Id)
            .OrderByDescending(x => x.SortOrder).ThenBy(x => x.Title).ToListAsync(ct);
        var articles = await Posts(s.Code)
            .OrderByDescending(x => x.Category == a.Category)
            .ThenByDescending(x => x.SortOrder).ThenByDescending(x => x.PublishedAt ?? x.CreatedAt)
            .Take(3).ToListAsync(ct);
        try
        {
            await db.Set<SeoArticle>().Where(x => x.Id == a.Id)
                .ExecuteUpdateAsync(u => u.SetProperty(x => x.ViewCount, x => x.ViewCount + 1), ct);
        }
        catch { /* đếm lượt xem không được làm hỏng trang */ }
        return Html(SeoPages.FeaturePage(s, a, others, articles));
    }

    [HttpGet("/bang-gia")]
    public async Task<IActionResult> Pricing(CancellationToken ct = default)
    {
        var s = Site;
        var rows = await db.ServicePackages.AsNoTracking()
            .Where(p => p.IsActive && p.IsPublic && (p.ProductLine == s.Code || p.ProductLine == "both"))
            .OrderBy(p => p.SortOrder).ThenBy(p => p.Name).ToListAsync(ct);
        var plans = rows.Select(p =>
        {
            var mods = FeatureModuleCatalog.DescribePublicModules(
                Infrastructure.Helpers.StorePackageHelper.DeserializeModules(p.AllowedModules));
            return new SeoPages.PricingPlan(
                p.Name, p.Description, p.MonthlyPrice, p.YearlyPrice,
                // Đăng ký tự phục vụ: số ngày dùng thử = thời hạn mặc định của gói (RegisterCommandHandler).
                p.TrialDays > 0 ? p.TrialDays : p.DefaultDurationDays,
                p.MaxUsers, p.MaxDevices, p.MaxBranches, p.Badge, p.IsFeatured,
                string.IsNullOrWhiteSpace(p.Highlights) ? [] : p.Highlights.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries),
                mods.GroupBy(m => m.Category)
                    .Select(g => (g.Key, (IReadOnlyList<string>)g.Select(m => m.DisplayName).Distinct().ToList()))
                    .ToList());
        }).ToList();
        return Html(SeoPages.PricingPage(s, plans));
    }

    [HttpGet("/tai-lieu")]
    public IActionResult Resources() => Html(SeoPages.ResourcesPage(Site), cacheSeconds: 600);

    /// <summary>Tải file Excel (liên kết trả về sau khi điền form; robots chặn thư mục này).</summary>
    [HttpGet("/tai-lieu/tai/{slug}")]
    public IActionResult Download(string slug)
    {
        var r = SeoResources.Find(Site.Code, slug) ?? SeoResources.All.FirstOrDefault(x => x.Slug == slug);
        if (r == null) return Html(SeoPages.NotFoundPage(Site), 404, 60);
        using var wb = r.Build();
        using var ms = new MemoryStream();
        wb.SaveAs(ms);
        Response.Headers["X-Robots-Tag"] = "noindex";
        return File(ms.ToArray(), "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", r.FileName);
    }

    public record LeadDto(string? Name, string? Phone, string? Company, string? InterestedPlan, string? Notes, string? Website);

    /// <summary>Form tư vấn / báo giá trên trang tính năng và bảng giá.</summary>
    [HttpPost("/api/public/leads")]
    [EnableRateLimiting("public-form")]
    public Task<IActionResult> Lead([FromBody] LeadDto dto, CancellationToken ct = default) =>
        SaveLeadAsync(dto, Site.Code == "pos" ? "SeoPos" : "SeoHrm", dto.InterestedPlan, null, null, ct);

    /// <summary>Đổi tên + SĐT lấy liên kết tải tài liệu.</summary>
    [HttpPost("/api/public/resources/{slug}")]
    [EnableRateLimiting("public-form")]
    public async Task<IActionResult> ResourceLead(string slug, [FromBody] LeadDto dto, CancellationToken ct = default)
    {
        var r = SeoResources.Find(Site.Code, slug) ?? SeoResources.All.FirstOrDefault(x => x.Slug == slug);
        if (r == null) return NotFound(new { isSuccess = false, message = "Không tìm thấy tài liệu" });
        return await SaveLeadAsync(dto, "TaiLieu", r.Title, $"Tải tài liệu: {r.Title}", "/tai-lieu/tai/" + r.Slug, ct);
    }

    async Task<IActionResult> SaveLeadAsync(LeadDto dto, string source, string? plan, string? notes, string? downloadUrl, CancellationToken ct)
    {
        static string? T(string? v, int max)
        {
            var x = v?.Trim();
            return string.IsNullOrEmpty(x) ? null : x.Length > max ? x[..max] : x;
        }
        if (!string.IsNullOrWhiteSpace(dto.Website)) return BadRequest(new { isSuccess = false, message = "Yêu cầu không hợp lệ" });
        var name = T(dto.Name, 150);
        var phone = T(dto.Phone, 30) ?? "";
        var normalized = Regex.Replace(phone, "[^0-9]", "");
        if (name == null) return BadRequest(new { isSuccess = false, message = "Vui lòng nhập họ và tên" });
        if (normalized.Length is < 9 or > 15) return BadRequest(new { isSuccess = false, message = "Số điện thoại không hợp lệ" });

        // Cùng SĐT gửi lại trong 10 phút: không ghi trùng, vẫn trả liên kết tải.
        var since = DateTime.UtcNow.AddMinutes(-10);
        var dup = await db.ConsultationRequests.AnyAsync(x => x.NormalizedPhone == normalized && x.Source == source && x.CreatedAt >= since, ct);
        if (!dup)
        {
            var page = Request.Headers.Referer.ToString();
            db.ConsultationRequests.Add(new ConsultationRequest
            {
                Id = Guid.NewGuid(),
                Name = name,
                Phone = phone,
                NormalizedPhone = normalized,
                Company = T(dto.Company, 200),
                InterestedPlan = T(plan, 100),
                Notes = T(string.Join(" · ", new[] { notes, T(dto.Notes, 600), string.IsNullOrEmpty(page) ? null : "Trang: " + page }
                    .Where(x => !string.IsNullOrWhiteSpace(x))), 1000),
                Status = "New",
                Source = source,
                ClientIp = HttpContext.Connection.RemoteIpAddress?.ToString(),
                UserAgent = T(Request.Headers.UserAgent.ToString(), 500),
                IsActive = true,
                CreatedAt = DateTime.UtcNow,
                CreatedBy = "PublicSeo",
            });
            await db.SaveChangesAsync(ct);
        }
        return Ok(new { isSuccess = true, data = new { downloadUrl } });
    }

    /// <summary>Bài viết mới cho trang chủ (JSON).</summary>
    [HttpGet("/api/public/articles")]
    public async Task<IActionResult> Latest([FromQuery] int take = 6, CancellationToken ct = default)
    {
        var s = Site;
        take = Math.Clamp(take, 1, 12);
        var items = await Posts(s.Code).OrderByDescending(a => a.SortOrder).ThenByDescending(a => a.PublishedAt ?? a.CreatedAt)
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

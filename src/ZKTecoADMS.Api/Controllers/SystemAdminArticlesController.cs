using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Api.Seo;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>Super Admin soạn bài viết SEO cho sboxhrm.com / sboxpos.com (Markdown, xem trước, xuất bản).</summary>
[ApiController]
[Authorize(Roles = nameof(Roles.SuperAdmin))]
[Route("api/system-admin/articles")]
public class SystemAdminArticlesController(ZKTecoDbContext db) : AuthenticatedControllerBase
{
    public record ArticleSaveDto(
        string Site, string Title, string? Slug, string? MetaTitle, string? MetaDescription, string? Keywords,
        string? Summary, string ContentMarkdown, string? CoverImageUrl, string? Category, string? AuthorName,
        bool IsPublished, DateTime? PublishedAt, int SortOrder = 0, string? PageType = null);

    public record PreviewDto(string? ContentMarkdown);

    DbSet<SeoArticle> Articles => db.Set<SeoArticle>();

    static object Map(SeoArticle a)
    {
        var site = a.Site == "pos" ? SeoPages.Pos : SeoPages.Hrm;
        var plain = SeoMarkdown.PlainText(a.ContentMarkdown);
        return new
        {
            a.Id, a.Site, a.PageType, a.Slug, a.Title, a.MetaTitle, a.MetaDescription, a.Keywords, a.Summary, a.ContentMarkdown,
            a.CoverImageUrl, a.Category, a.AuthorName, a.IsPublished, a.PublishedAt, a.SortOrder, a.ViewCount,
            a.CreatedAt, a.UpdatedAt,
            url = a.PageType == "feature" ? SeoPages.FeatureUrl(site, a) : SeoPages.ArticleUrl(site, a),
            wordCount = plain.Split(' ', StringSplitOptions.RemoveEmptyEntries).Length,
            seoChecks = Checks(a),
        };
    }

    /// <summary>Gợi ý SEO cơ bản để người soạn sửa trước khi xuất bản.</summary>
    static List<string> Checks(SeoArticle a)
    {
        var w = new List<string>();
        var title = string.IsNullOrWhiteSpace(a.MetaTitle) ? a.Title : a.MetaTitle!;
        if (title.Length > 65) w.Add($"Tiêu đề Google dài {title.Length} ký tự — nên ≤ 60.");
        if (title.Length < 25) w.Add("Tiêu đề Google ngắn — nên 40–60 ký tự, có từ khóa chính.");
        var desc = a.MetaDescription ?? a.Summary ?? "";
        if (desc.Length == 0) w.Add("Chưa có mô tả Google (Meta description).");
        else if (desc.Length > 170) w.Add($"Mô tả Google dài {desc.Length} ký tự — nên 120–160.");
        else if (desc.Length < 80) w.Add("Mô tả Google ngắn — nên 120–160 ký tự.");
        var words = SeoMarkdown.PlainText(a.ContentMarkdown).Split(' ', StringSplitOptions.RemoveEmptyEntries).Length;
        if (words < 600) w.Add($"Nội dung {words} từ — bài SEO nên từ 800 từ trở lên.");
        if (!a.ContentMarkdown.Contains("\n## ") && !a.ContentMarkdown.StartsWith("## ")) w.Add("Chưa có tiêu đề mục (## …) — chia bài thành các mục giúp Google hiểu cấu trúc.");
        if (!a.ContentMarkdown.Contains("](/")) w.Add("Chưa có liên kết nội bộ (vd [đăng ký dùng thử](/register) hoặc tới bài khác).");
        if (string.IsNullOrWhiteSpace(a.CoverImageUrl)) w.Add("Chưa có ảnh bìa — chia sẻ Facebook/Zalo sẽ dùng ảnh mặc định.");
        return w;
    }

    [HttpGet]
    public async Task<ActionResult<AppResponse<object>>> List([FromQuery] string? site, [FromQuery] string? search, CancellationToken ct = default)
    {
        var q = Articles.AsNoTracking().Where(a => a.Deleted == null);
        if (!string.IsNullOrWhiteSpace(site)) q = q.Where(a => a.Site == site);
        if (!string.IsNullOrWhiteSpace(search))
        {
            var s = search.Trim().ToLower();
            q = q.Where(a => a.Title.ToLower().Contains(s) || a.Slug.Contains(s) || (a.Category != null && a.Category.ToLower().Contains(s)));
        }
        var rows = await q.OrderByDescending(a => a.UpdatedAt ?? a.CreatedAt).Take(500).ToListAsync(ct);
        return Ok(AppResponse<object>.Success(rows.Select(Map)));
    }

    [HttpGet("{id:guid}")]
    public async Task<ActionResult<AppResponse<object>>> Get(Guid id, CancellationToken ct = default)
    {
        var a = await Articles.AsNoTracking().FirstOrDefaultAsync(x => x.Id == id && x.Deleted == null, ct);
        return a == null ? NotFound(AppResponse<object>.Fail("Không tìm thấy bài viết")) : Ok(AppResponse<object>.Success(Map(a)));
    }

    [HttpPost("preview")]
    public ActionResult<AppResponse<object>> Preview([FromBody] PreviewDto dto) =>
        Ok(AppResponse<object>.Success(new { html = SeoMarkdown.ToHtml(dto.ContentMarkdown) }));

    [HttpPost]
    public async Task<ActionResult<AppResponse<object>>> Create([FromBody] ArticleSaveDto dto, CancellationToken ct = default)
    {
        var a = new SeoArticle { Id = Guid.NewGuid(), CreatedBy = CurrentUserEmail, IsActive = true };
        var err = await ApplyAsync(a, dto, ct);
        if (err != null) return BadRequest(AppResponse<object>.Fail(err));
        Articles.Add(a);
        await db.SaveChangesAsync(ct);
        return Ok(AppResponse<object>.Success(Map(a)));
    }

    [HttpPut("{id:guid}")]
    public async Task<ActionResult<AppResponse<object>>> Update(Guid id, [FromBody] ArticleSaveDto dto, CancellationToken ct = default)
    {
        var a = await Articles.AsTracking().FirstOrDefaultAsync(x => x.Id == id && x.Deleted == null, ct);
        if (a == null) return NotFound(AppResponse<object>.Fail("Không tìm thấy bài viết"));
        var err = await ApplyAsync(a, dto, ct);
        if (err != null) return BadRequest(AppResponse<object>.Fail(err));
        a.UpdatedAt = DateTime.UtcNow;
        a.UpdatedBy = CurrentUserEmail;
        await db.SaveChangesAsync(ct);
        return Ok(AppResponse<object>.Success(Map(a)));
    }

    [HttpDelete("{id:guid}")]
    public async Task<ActionResult<AppResponse<object>>> Delete(Guid id, CancellationToken ct = default)
    {
        var a = await Articles.AsTracking().FirstOrDefaultAsync(x => x.Id == id && x.Deleted == null, ct);
        if (a == null) return NotFound(AppResponse<object>.Fail("Không tìm thấy bài viết"));
        a.Deleted = DateTime.UtcNow;
        a.DeletedBy = CurrentUserEmail;
        a.IsPublished = false;
        // Giải phóng đường dẫn để bài mới dùng lại được (chỉ mục duy nhất Site + Slug).
        a.Slug = $"{a.Slug}--xoa-{DateTime.UtcNow:yyyyMMddHHmmss}";
        if (a.Slug.Length > 200) a.Slug = a.Slug[^200..];
        await db.SaveChangesAsync(ct);
        return Ok(AppResponse<object>.Success(new { id }));
    }

    async Task<string?> ApplyAsync(SeoArticle a, ArticleSaveDto dto, CancellationToken ct)
    {
        var site = (dto.Site ?? "").Trim().ToLowerInvariant();
        if (site is not ("hrm" or "pos")) return "Chọn trang: SBOX HRM (sboxhrm.com) hoặc SBOX POS (sboxpos.com).";
        var title = (dto.Title ?? "").Trim();
        if (title.Length < 5) return "Tiêu đề quá ngắn.";
        if (string.IsNullOrWhiteSpace(dto.ContentMarkdown)) return "Chưa có nội dung.";
        var slug = SeoMarkdown.Slugify(string.IsNullOrWhiteSpace(dto.Slug) ? title : dto.Slug!);
        if (slug.Length < 3) return "Đường dẫn (slug) không hợp lệ.";
        var taken = await Articles.AnyAsync(x => x.Id != a.Id && x.Site == site && x.Slug == slug, ct);
        if (taken) return $"Đường dẫn «{slug}» đã có bài khác trên site này — đổi slug.";

        static string? T(string? v, int max)
        {
            var s = v?.Trim();
            if (string.IsNullOrEmpty(s)) return null;
            return s.Length > max ? s[..max] : s;
        }

        a.Site = site;
        a.PageType = dto.PageType == "feature" ? "feature" : "article";
        a.Title = title.Length > 300 ? title[..300] : title;
        a.Slug = slug;
        a.MetaTitle = T(dto.MetaTitle, 300);
        a.MetaDescription = T(dto.MetaDescription, 500);
        a.Keywords = T(dto.Keywords, 500);
        a.Summary = T(dto.Summary, 1000);
        a.ContentMarkdown = dto.ContentMarkdown.Trim();
        a.CoverImageUrl = SeoMarkdown.SafeUrl(dto.CoverImageUrl) is { } cover ? T(cover, 500) : null;
        a.Category = T(dto.Category, 100);
        a.AuthorName = T(dto.AuthorName, 200);
        a.SortOrder = dto.SortOrder;
        if (dto.IsPublished && !a.IsPublished) a.PublishedAt = dto.PublishedAt ?? a.PublishedAt ?? DateTime.UtcNow;
        else if (dto.PublishedAt.HasValue) a.PublishedAt = dto.PublishedAt;
        a.IsPublished = dto.IsPublished;
        return null;
    }
}

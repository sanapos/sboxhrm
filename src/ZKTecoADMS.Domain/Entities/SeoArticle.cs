using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>Bài viết SEO hiển thị công khai tại /bai-viet/{slug} trên sboxhrm.com (hrm) hoặc sboxpos.com (pos).</summary>
public class SeoArticle : AuditableEntity<Guid>
{
    /// <summary>hrm · pos — mỗi bài thuộc một tên miền (tránh trùng nội dung giữa hai site).</summary>
    [MaxLength(10)]
    public string Site { get; set; } = "hrm";

    [MaxLength(200)]
    public string Slug { get; set; } = string.Empty;

    [MaxLength(300)]
    public string Title { get; set; } = string.Empty;

    /// <summary>Tiêu đề trên Google (≤ 60 ký tự); trống thì dùng Title.</summary>
    [MaxLength(300)]
    public string? MetaTitle { get; set; }

    /// <summary>Mô tả trên Google (≤ 160 ký tự).</summary>
    [MaxLength(500)]
    public string? MetaDescription { get; set; }

    [MaxLength(500)]
    public string? Keywords { get; set; }

    [MaxLength(1000)]
    public string? Summary { get; set; }

    /// <summary>Nội dung Markdown (tiêu đề ##, danh sách, **đậm**, [liên kết](url), ![ảnh](url), bảng).</summary>
    public string ContentMarkdown { get; set; } = string.Empty;

    [MaxLength(500)]
    public string? CoverImageUrl { get; set; }

    [MaxLength(100)]
    public string? Category { get; set; }

    [MaxLength(200)]
    public string? AuthorName { get; set; }

    public bool IsPublished { get; set; }

    public DateTime? PublishedAt { get; set; }

    public int SortOrder { get; set; }

    public int ViewCount { get; set; }
}

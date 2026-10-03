using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Seo;

/// <summary>
/// Nạp bài viết SEO mẫu từ Seo/Seed/*.md (nhúng trong assembly). Mỗi bài chỉ nạp một lần — đánh dấu
/// trong SboxDataMigrations (seo-seed-{site}-{slug}) nên bài bị Super Admin xóa sẽ không tự xuất hiện lại.
/// </summary>
public static class SeoArticleSeeder
{
    const string Prefix = "Sbox.SeoSeed.";

    public record SeedArticle(
        string Site, string Slug, string Title, string? MetaTitle, string? MetaDescription, string? Keywords,
        string? Summary, string? Category, string? Cover, int SortOrder, string Body);

    public static async Task SeedAsync(ZKTecoDbContext db, ILogger logger, CancellationToken ct = default)
    {
        try
        {
            var asm = typeof(SeoArticleSeeder).Assembly;
            foreach (var name in asm.GetManifestResourceNames().Where(n => n.StartsWith(Prefix, StringComparison.Ordinal)).Order())
            {
                await using var stream = asm.GetManifestResourceStream(name);
                if (stream == null) continue;
                using var reader = new StreamReader(stream);
                var seed = Parse(await reader.ReadToEndAsync(ct));
                if (seed == null) { logger.LogWarning("SEO seed {Name}: thiếu front matter", name); continue; }

                var marker = $"seo-seed-{seed.Site}-{seed.Slug}";
                if (marker.Length > 100) marker = marker[..100];
                var done = await db.Database
                    .SqlQuery<int>($"SELECT 1 AS \"Value\" FROM \"SboxDataMigrations\" WHERE \"Id\" = {marker}")
                    .AnyAsync(ct);
                if (done) continue;

                var exists = await db.Set<SeoArticle>().AnyAsync(a => a.Site == seed.Site && a.Slug == seed.Slug, ct);
                if (!exists)
                {
                    db.Set<SeoArticle>().Add(new SeoArticle
                    {
                        Id = Guid.NewGuid(),
                        Site = seed.Site,
                        Slug = seed.Slug,
                        Title = seed.Title,
                        MetaTitle = seed.MetaTitle,
                        MetaDescription = seed.MetaDescription,
                        Keywords = seed.Keywords,
                        Summary = seed.Summary,
                        Category = seed.Category,
                        CoverImageUrl = seed.Cover,
                        AuthorName = "Đội ngũ SBOX",
                        ContentMarkdown = seed.Body,
                        SortOrder = seed.SortOrder,
                        IsPublished = true,
                        PublishedAt = DateTime.UtcNow,
                        IsActive = true,
                        CreatedBy = "seed",
                    });
                    await db.SaveChangesAsync(ct);
                }
                await db.Database.ExecuteSqlInterpolatedAsync(
                    $"INSERT INTO \"SboxDataMigrations\" (\"Id\") VALUES ({marker}) ON CONFLICT DO NOTHING", ct);
                logger.LogInformation("SEO seed: {Site}/{Slug}", seed.Site, seed.Slug);
            }
        }
        catch (Exception ex)
        {
            // Bảng chưa có (CSDL mới) hoặc lỗi khác — không chặn khởi động API.
            logger.LogWarning(ex, "SEO article seed skipped");
        }
    }

    /// <summary>Front matter dạng «key: value» giữa hai dòng ---, phần còn lại là nội dung Markdown.</summary>
    public static SeedArticle? Parse(string text)
    {
        var t = text.Replace("\r\n", "\n").TrimStart('﻿');
        if (!t.StartsWith("---\n")) return null;
        var end = t.IndexOf("\n---\n", 4, StringComparison.Ordinal);
        if (end < 0) return null;
        var meta = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var line in t[4..end].Split('\n'))
        {
            var i = line.IndexOf(':');
            if (i <= 0) continue;
            meta[line[..i].Trim()] = line[(i + 1)..].Trim();
        }
        string? G(string k) => meta.TryGetValue(k, out var v) && v.Length > 0 ? v : null;
        var site = G("site");
        var slug = G("slug");
        var title = G("title");
        if (site is not ("hrm" or "pos") || slug == null || title == null) return null;
        return new SeedArticle(site, slug, title, G("metaTitle"), G("metaDescription"), G("keywords"),
            G("summary"), G("category"), G("cover"), int.TryParse(G("sortOrder"), out var so) ? so : 0,
            t[(end + 5)..].Trim());
    }
}

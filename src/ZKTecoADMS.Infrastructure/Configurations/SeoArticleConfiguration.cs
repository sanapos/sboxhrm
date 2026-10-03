using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class SeoArticleConfiguration : IEntityTypeConfiguration<SeoArticle>
{
    public void Configure(EntityTypeBuilder<SeoArticle> builder)
    {
        builder.ToTable("SeoArticles");
        builder.HasKey(x => x.Id);
        builder.Property(x => x.Site).IsRequired().HasMaxLength(10);
        builder.Property(x => x.Slug).IsRequired().HasMaxLength(200);
        builder.Property(x => x.Title).IsRequired().HasMaxLength(300);
        builder.Property(x => x.MetaTitle).HasMaxLength(300);
        builder.Property(x => x.MetaDescription).HasMaxLength(500);
        builder.Property(x => x.Keywords).HasMaxLength(500);
        builder.Property(x => x.Summary).HasMaxLength(1000);
        builder.Property(x => x.CoverImageUrl).HasMaxLength(500);
        builder.Property(x => x.Category).HasMaxLength(100);
        builder.Property(x => x.AuthorName).HasMaxLength(200);
        builder.HasIndex(x => new { x.Site, x.Slug }).IsUnique();
        builder.HasIndex(x => new { x.Site, x.IsPublished, x.PublishedAt });
    }
}

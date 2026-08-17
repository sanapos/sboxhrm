using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class PosProductSampleCatalogConfiguration : IEntityTypeConfiguration<PosProductSampleCatalog>
{
    public void Configure(EntityTypeBuilder<PosProductSampleCatalog> builder)
    {
        builder.ToTable("PosProductSampleCatalog");
        builder.HasKey(x => x.Id);
        builder.Property(x => x.Barcode).HasMaxLength(50);
        builder.Property(x => x.Name).IsRequired().HasMaxLength(500);
        builder.Property(x => x.UnitName).HasMaxLength(100);
        builder.Property(x => x.BrandName).HasMaxLength(200);
        builder.Property(x => x.CategoryName).HasMaxLength(200);
        builder.Property(x => x.ImageUrl).HasMaxLength(1000);
        builder.Property(x => x.Description).HasMaxLength(2000);
        builder.Property(x => x.DefaultPrice).HasPrecision(18, 2);
        builder.Property(x => x.DefaultCostPrice).HasPrecision(18, 2);
        builder.Property(x => x.VatRate).HasPrecision(9, 4);
        builder.HasIndex(x => x.Barcode);
        builder.HasIndex(x => new { x.Kind, x.SortOrder });
        builder.HasIndex(x => x.ProductType);
        builder.HasIndex(x => x.Name);
    }
}

using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class PosBarcodeCatalogConfiguration : IEntityTypeConfiguration<PosBarcodeCatalog>
{
    public void Configure(EntityTypeBuilder<PosBarcodeCatalog> builder)
    {
        builder.ToTable("PosBarcodeCatalog");
        builder.HasKey(x => x.Id);
        builder.Property(x => x.Barcode).IsRequired().HasMaxLength(50);
        builder.Property(x => x.Name).IsRequired().HasMaxLength(500);
        builder.Property(x => x.UnitName).HasMaxLength(100);
        builder.Property(x => x.BrandName).HasMaxLength(200);
        builder.Property(x => x.CategoryName).HasMaxLength(200);
        builder.Property(x => x.ImageUrl).HasMaxLength(1000);
        builder.HasIndex(x => new { x.StoreId, x.Barcode });
        builder.HasOne(x => x.Store).WithMany().HasForeignKey(x => x.StoreId).OnDelete(DeleteBehavior.Cascade);
    }
}

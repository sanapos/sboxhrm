using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class PosPriceListConfiguration : IEntityTypeConfiguration<PosPriceList>
{
    public void Configure(EntityTypeBuilder<PosPriceList> builder)
    {
        builder.ToTable("PosPriceLists");
        builder.HasKey(x => x.Id);
        builder.Property(x => x.Name).IsRequired().HasMaxLength(100);
        builder.HasIndex(x => new { x.StoreId, x.Name });
        builder.HasOne(x => x.Store).WithMany().HasForeignKey(x => x.StoreId).OnDelete(DeleteBehavior.Cascade);
    }
}

public class PosPriceListItemConfiguration : IEntityTypeConfiguration<PosPriceListItem>
{
    public void Configure(EntityTypeBuilder<PosPriceListItem> builder)
    {
        builder.ToTable("PosPriceListItems");
        builder.HasKey(x => x.Id);
        builder.Property(x => x.Price).HasPrecision(18, 2);
        builder.HasIndex(x => new { x.PriceListId, x.ProductId, x.VariantId, x.UnitId });
        builder.HasOne(x => x.PriceList).WithMany(x => x.Items).HasForeignKey(x => x.PriceListId)
            .OnDelete(DeleteBehavior.Cascade);
        builder.HasOne(x => x.Product).WithMany().HasForeignKey(x => x.ProductId).OnDelete(DeleteBehavior.Cascade);
        builder.HasOne(x => x.Variant).WithMany().HasForeignKey(x => x.VariantId).OnDelete(DeleteBehavior.SetNull);
        builder.HasOne(x => x.Unit).WithMany().HasForeignKey(x => x.UnitId).OnDelete(DeleteBehavior.SetNull);
    }
}

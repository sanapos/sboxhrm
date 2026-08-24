using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class PosQrMenuItemConfiguration : IEntityTypeConfiguration<PosQrMenuItem>
{
    public void Configure(EntityTypeBuilder<PosQrMenuItem> builder)
    {
        builder.ToTable("PosQrMenuItems");
        builder.HasKey(x => x.Id);
        builder.Property(x => x.QrPrice).HasPrecision(18, 2);
        builder.HasIndex(x => new { x.StoreId, x.ProductId }).IsUnique();
        builder.HasOne(x => x.Store).WithMany().HasForeignKey(x => x.StoreId).OnDelete(DeleteBehavior.Cascade);
        builder.HasOne(x => x.Product).WithMany().HasForeignKey(x => x.ProductId).OnDelete(DeleteBehavior.Cascade);
    }
}

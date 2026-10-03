using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class PosSaleReturnLineConfiguration : IEntityTypeConfiguration<PosSaleReturnLine>
{
    public void Configure(EntityTypeBuilder<PosSaleReturnLine> builder)
    {
        builder.ToTable("PosSaleReturnLines");
        builder.HasKey(x => x.Id);
        builder.Property(x => x.ReturnNo).IsRequired().HasMaxLength(50);
        builder.Property(x => x.Qty).HasPrecision(18, 4);
        builder.Property(x => x.RefundAmount).HasPrecision(18, 2);
        builder.Property(x => x.CostAmount).HasPrecision(18, 4);
        builder.HasIndex(x => x.SaleOrderId);
        builder.HasIndex(x => new { x.StoreId, x.CreatedAt });
        builder.HasIndex(x => new { x.StoreId, x.ReturnNo });
    }
}

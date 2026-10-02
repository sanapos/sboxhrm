using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class PosQuotePaymentStageConfiguration : IEntityTypeConfiguration<PosQuotePaymentStage>
{
    public void Configure(EntityTypeBuilder<PosQuotePaymentStage> builder)
    {
        builder.ToTable("PosQuotePaymentStages");
        builder.HasKey(x => x.Id);
        builder.Property(x => x.Title).IsRequired().HasMaxLength(200);
        builder.Property(x => x.Note).HasMaxLength(500);
        builder.Property(x => x.Percent).HasPrecision(5, 2);
        builder.Property(x => x.Amount).HasPrecision(18, 2);
        builder.HasIndex(x => x.QuoteId);
        builder.HasOne(x => x.Quote).WithMany(x => x.PaymentStages).HasForeignKey(x => x.QuoteId).OnDelete(DeleteBehavior.Cascade);
    }
}

public class PosQuotePaymentConfiguration : IEntityTypeConfiguration<PosQuotePayment>
{
    public void Configure(EntityTypeBuilder<PosQuotePayment> builder)
    {
        builder.ToTable("PosQuotePayments");
        builder.HasKey(x => x.Id);
        builder.Property(x => x.Amount).HasPrecision(18, 2);
        builder.Property(x => x.PaymentMethod).HasMaxLength(50);
        builder.Property(x => x.Note).HasMaxLength(500);
        builder.Property(x => x.CollectedBy).HasMaxLength(200);
        builder.HasIndex(x => x.QuoteId);
        builder.HasIndex(x => new { x.StoreId, x.PaidAt });
        builder.HasOne(x => x.Quote).WithMany(x => x.Payments).HasForeignKey(x => x.QuoteId).OnDelete(DeleteBehavior.Cascade);
    }
}

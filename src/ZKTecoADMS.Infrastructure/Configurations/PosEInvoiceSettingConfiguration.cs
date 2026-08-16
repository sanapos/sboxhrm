using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class PosEInvoiceSettingConfiguration : IEntityTypeConfiguration<PosEInvoiceSetting>
{
    public void Configure(EntityTypeBuilder<PosEInvoiceSetting> builder)
    {
        builder.ToTable("PosEInvoiceSettings");
        builder.HasKey(x => x.Id);
        builder.Property(x => x.Provider).IsRequired().HasMaxLength(20);
        builder.Property(x => x.ApiBaseUrl).HasMaxLength(300);
        builder.Property(x => x.Username).HasMaxLength(100);
        builder.Property(x => x.Password).HasMaxLength(200);
        builder.Property(x => x.SupplierTaxCode).HasMaxLength(20);
        builder.Property(x => x.TemplateCode).HasMaxLength(20);
        builder.Property(x => x.InvoiceSeries).HasMaxLength(25);
        builder.Property(x => x.InvoiceType).HasMaxLength(10);
        builder.Property(x => x.TaxMode).HasMaxLength(20);
        builder.Property(x => x.DefaultTaxPercent).HasPrecision(18, 2);
        builder.HasIndex(x => x.StoreId).IsUnique();
        builder.HasOne(x => x.Store).WithMany().HasForeignKey(x => x.StoreId).OnDelete(DeleteBehavior.Cascade);
    }
}

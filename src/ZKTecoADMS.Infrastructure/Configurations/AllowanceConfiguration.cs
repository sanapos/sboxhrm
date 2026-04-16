using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class AllowanceConfiguration : IEntityTypeConfiguration<Allowance>
{
    public void Configure(EntityTypeBuilder<Allowance> builder)
    {
        builder.HasKey(a => a.Id);

        builder.Property(a => a.Name)
            .IsRequired()
            .HasMaxLength(200);

        builder.Property(a => a.Code)
            .HasMaxLength(50);

        builder.Property(a => a.Description)
            .HasMaxLength(500);

        builder.Property(a => a.Amount)
            .HasPrecision(18, 2);

        builder.Property(a => a.Currency)
            .HasMaxLength(10)
            .HasDefaultValue("VND");

        builder.Property(a => a.Type)
            .HasConversion<int>();

        // Indexes
        builder.HasIndex(a => a.Type)
            .HasDatabaseName("IX_Allowances_Type");

        builder.HasIndex(a => a.IsActive)
            .HasDatabaseName("IX_Allowances_IsActive");
    }
}

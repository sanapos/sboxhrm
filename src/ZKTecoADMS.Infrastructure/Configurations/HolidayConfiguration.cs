using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class HolidayConfiguration : IEntityTypeConfiguration<Holiday>
{
    public void Configure(EntityTypeBuilder<Holiday> builder)
    {
        builder.ToTable("Holidays");

        builder.HasKey(h => h.Id);

        builder.Property(h => h.Name)
            .IsRequired()
            .HasMaxLength(200);

        builder.Property(h => h.Date)
            .IsRequired();

        builder.Property(h => h.Description)
            .HasMaxLength(500);

        builder.Property(h => h.Region)
            .HasMaxLength(50)
            .HasDefaultValue("Vietnam");

        builder.Property(h => h.IsRecurring)
            .HasDefaultValue(true);

        builder.Property(h => h.IsActive)
            .HasDefaultValue(true);

        // Create index on Date for faster queries
        builder.HasIndex(h => h.Date);

        // Create index on Region
        builder.HasIndex(h => h.Region);

        // Composite index for active holidays by date and region
        builder.HasIndex(h => new { h.Date, h.Region, h.IsActive });
    }
}

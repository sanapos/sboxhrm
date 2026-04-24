using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class MaintenanceWindowConfiguration : IEntityTypeConfiguration<MaintenanceWindow>
{
    public void Configure(EntityTypeBuilder<MaintenanceWindow> builder)
    {
        builder.ToTable("MaintenanceWindows");
        builder.HasKey(x => x.Id);

        builder.Property(x => x.Title).IsRequired().HasMaxLength(200);
        builder.Property(x => x.Message).IsRequired();
        builder.Property(x => x.AffectedModulesJson).HasColumnType("jsonb");
        builder.Property(x => x.NotifyBeforeMinutesCsv).HasMaxLength(100);
        builder.Property(x => x.NotifiedMinutesCsv).HasMaxLength(100);

        builder.HasIndex(x => new { x.IsActive, x.StartAt, x.EndAt })
            .HasDatabaseName("IX_MaintenanceWindows_Active_Range");
    }
}

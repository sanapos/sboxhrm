using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class SyncLogConfiguration : IEntityTypeConfiguration<SyncLog>
{
    public void Configure(EntityTypeBuilder<SyncLog> builder)
    {
        builder.HasKey(e => e.Id);
        builder.HasIndex(e => e.DeviceId);
        builder.HasIndex(e => e.CreatedAt);

        builder.HasOne(e => e.Device)
            .WithMany(d => d.SyncLogs)
            .HasForeignKey(e => e.DeviceId)
            .OnDelete(DeleteBehavior.Cascade);
    }
}
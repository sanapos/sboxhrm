

using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class DeviceInfoConfiguration : IEntityTypeConfiguration<DeviceInfo>
{
    public void Configure(EntityTypeBuilder<DeviceInfo> builder)
    {
        builder.HasKey(e => e.Id);

        builder.Property(e => e.Platform).HasMaxLength(100);
        builder.Property(e => e.PushVersion).HasMaxLength(50);
        builder.Property(e => e.DeviceModelName).HasMaxLength(200);
        builder.Property(e => e.OemVendor).HasMaxLength(100);
        builder.Property(e => e.EngineProfile).HasMaxLength(50);
        builder.Property(e => e.CapabilityNotes).HasMaxLength(1000);

        builder.HasOne(di => di.Device)
            .WithOne(d => d.DeviceInfo)
            .HasForeignKey<DeviceInfo>(di => di.DeviceId);
    }
}
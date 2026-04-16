using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class DeviceSettingConfiguration : IEntityTypeConfiguration<DeviceSetting>
{
    public void Configure(EntityTypeBuilder<DeviceSetting> builder)
    {
        builder.HasKey(e => e.Id);
        builder.HasIndex(e => new { e.DeviceId, e.SettingKey }).IsUnique();

        builder.HasOne(e => e.Device)
            .WithMany(d => d.DeviceSettings)
            .HasForeignKey(e => e.DeviceId)
            .OnDelete(DeleteBehavior.Cascade);
    }
}
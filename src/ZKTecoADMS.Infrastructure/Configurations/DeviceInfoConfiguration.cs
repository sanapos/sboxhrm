

using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class DeviceInfoConfiguration : IEntityTypeConfiguration<DeviceInfo>
{
    public void Configure(EntityTypeBuilder<DeviceInfo> builder)
    {
        builder.HasKey(e => e.Id);

        builder.HasOne(di => di.Device)
            .WithOne(d => d.DeviceInfo)
            .HasForeignKey<DeviceInfo>(di => di.DeviceId);
    }
}
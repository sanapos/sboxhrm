using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class DeviceConfiguration : IEntityTypeConfiguration<Device>
{
    public void Configure(EntityTypeBuilder<Device> builder)
    {
        builder.HasKey(e => e.Id);
        builder.HasIndex(e => e.SerialNumber).IsUnique();

        builder.HasOne(d => d.DeviceInfo)
            .WithOne(di => di.Device)
            .HasForeignKey<Device>(d => d.DeviceInfoId);

        builder.HasOne(d => d.Manager)
            .WithMany(m => m.Devices)
            .HasForeignKey(d => d.ManagerId)
            .OnDelete(DeleteBehavior.Cascade);
            
        // Relationship với Store
        builder.HasOne(d => d.Store)
            .WithMany(s => s.Devices)
            .HasForeignKey(d => d.StoreId)
            .OnDelete(DeleteBehavior.SetNull);
    }
}
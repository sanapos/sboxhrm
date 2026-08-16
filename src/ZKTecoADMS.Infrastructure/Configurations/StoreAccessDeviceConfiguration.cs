using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class StoreAccessDeviceConfiguration : IEntityTypeConfiguration<StoreAccessDevice>
{
    public void Configure(EntityTypeBuilder<StoreAccessDevice> builder)
    {
        builder.ToTable("StoreAccessDevices");
        builder.HasKey(x => x.Id);
        builder.Property(x => x.DeviceKey).IsRequired().HasMaxLength(80);
        builder.Property(x => x.Platform).IsRequired().HasMaxLength(20);
        builder.Property(x => x.DeviceName).HasMaxLength(200);
        builder.HasIndex(x => new { x.StoreId, x.DeviceKey }).IsUnique();
        builder.HasOne(x => x.Store).WithMany().HasForeignKey(x => x.StoreId).OnDelete(DeleteBehavior.Cascade);
    }
}

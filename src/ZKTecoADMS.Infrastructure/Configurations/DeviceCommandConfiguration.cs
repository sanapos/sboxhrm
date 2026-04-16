using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class DeviceCommandConfiguration : IEntityTypeConfiguration<DeviceCommand>
{
    public void Configure(EntityTypeBuilder<DeviceCommand> builder)
    {
        builder.HasKey(e => e.Id);
        builder.HasIndex(e => e.CommandId);
        
        builder.HasOne(e => e.Device)
            .WithMany(d => d.DeviceCommands)
            .HasForeignKey(e => e.DeviceId)
            .OnDelete(DeleteBehavior.Cascade);
    }
}
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class DeviceUserConfiguration : IEntityTypeConfiguration<DeviceUser>
{
    public void Configure(EntityTypeBuilder<DeviceUser> builder)
    {
        builder.HasKey(e => e.Id);
        builder.HasIndex(e => e.Pin);

        builder.HasOne(i => i.Device)
            .WithMany(i => i.Employees)
            .HasForeignKey(i => i.DeviceId)
            .OnDelete(DeleteBehavior.Cascade);
        
        builder.HasOne(i => i.Employee)
            .WithMany(e => e.DeviceUsers)
            .HasForeignKey(i => i.EmployeeId)
            .OnDelete(DeleteBehavior.Cascade)
            .IsRequired(false);
    }
}
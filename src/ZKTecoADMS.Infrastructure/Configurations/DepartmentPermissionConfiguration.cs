using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class DepartmentPermissionConfiguration : IEntityTypeConfiguration<DepartmentPermission>
{
    public void Configure(EntityTypeBuilder<DepartmentPermission> builder)
    {
        builder.HasKey(e => e.Id);

        builder.Property(e => e.GrantedBy).HasMaxLength(100);
        builder.Property(e => e.Note).HasMaxLength(500);

        builder.HasOne(dp => dp.User)
            .WithMany()
            .HasForeignKey(dp => dp.UserId)
            .OnDelete(DeleteBehavior.Cascade);

        builder.HasOne(dp => dp.Department)
            .WithMany()
            .HasForeignKey(dp => dp.DepartmentId)
            .OnDelete(DeleteBehavior.Cascade);

        builder.HasOne(dp => dp.Permission)
            .WithMany()
            .HasForeignKey(dp => dp.PermissionId)
            .OnDelete(DeleteBehavior.Cascade);

        builder.HasOne(dp => dp.Store)
            .WithMany()
            .HasForeignKey(dp => dp.StoreId)
            .OnDelete(DeleteBehavior.Cascade);

        // Unique: mỗi user chỉ có 1 record per (department, permission, store)
        builder.HasIndex(e => new { e.UserId, e.DepartmentId, e.PermissionId, e.StoreId })
            .IsUnique();

        builder.HasIndex(e => e.DepartmentId);
        builder.HasIndex(e => e.UserId);
    }
}

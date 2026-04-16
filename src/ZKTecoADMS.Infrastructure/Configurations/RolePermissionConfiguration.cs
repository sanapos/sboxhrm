using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class RolePermissionConfiguration : IEntityTypeConfiguration<RolePermission>
{
    public void Configure(EntityTypeBuilder<RolePermission> builder)
    {
        builder.HasKey(e => e.Id);
        
        builder.Property(e => e.RoleName)
            .IsRequired()
            .HasMaxLength(50);
        
        builder.Property(e => e.RoleDisplayName)
            .IsRequired()
            .HasMaxLength(100);
        
        builder.Property(e => e.CreatedBy)
            .HasMaxLength(100);
        
        // Relationship với Permission
        builder.HasOne(rp => rp.Permission)
            .WithMany(p => p.RolePermissions)
            .HasForeignKey(rp => rp.PermissionId)
            .OnDelete(DeleteBehavior.Cascade);
        
        // Relationship với Store (optional)
        builder.HasOne(rp => rp.Store)
            .WithMany()
            .HasForeignKey(rp => rp.StoreId)
            .OnDelete(DeleteBehavior.Cascade);
        
        // Index để tránh duplicate role-permission cho cùng store
        builder.HasIndex(e => new { e.RoleName, e.PermissionId, e.StoreId })
            .IsUnique();
    }
}

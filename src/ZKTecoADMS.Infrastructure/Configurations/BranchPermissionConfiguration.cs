using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class BranchPermissionConfiguration : IEntityTypeConfiguration<BranchPermission>
{
    public void Configure(EntityTypeBuilder<BranchPermission> builder)
    {
        builder.HasKey(e => e.Id);

        builder.Property(e => e.GrantedBy).HasMaxLength(100);
        builder.Property(e => e.Note).HasMaxLength(500);

        builder.HasOne(bp => bp.User)
            .WithMany()
            .HasForeignKey(bp => bp.UserId)
            .OnDelete(DeleteBehavior.Cascade);

        builder.HasOne(bp => bp.Branch)
            .WithMany()
            .HasForeignKey(bp => bp.BranchId)
            .OnDelete(DeleteBehavior.Cascade);

        builder.HasOne(bp => bp.Store)
            .WithMany()
            .HasForeignKey(bp => bp.StoreId)
            .OnDelete(DeleteBehavior.Cascade);

        // Unique: mỗi user chỉ có 1 record per (branch, store)
        builder.HasIndex(e => new { e.UserId, e.BranchId, e.StoreId })
            .IsUnique();

        builder.HasIndex(e => e.BranchId);
        builder.HasIndex(e => e.UserId);
    }
}

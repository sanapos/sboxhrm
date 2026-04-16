using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class BranchConfiguration : IEntityTypeConfiguration<Branch>
{
    public void Configure(EntityTypeBuilder<Branch> builder)
    {
        builder.ToTable("Branches");
        builder.HasKey(b => b.Id);

        builder.Property(b => b.Code).IsRequired().HasMaxLength(20);
        builder.Property(b => b.Name).IsRequired().HasMaxLength(200);
        builder.Property(b => b.Description).HasMaxLength(1000);
        builder.Property(b => b.Phone).HasMaxLength(20);
        builder.Property(b => b.Email).HasMaxLength(200);
        builder.Property(b => b.Address).HasMaxLength(500);
        builder.Property(b => b.City).HasMaxLength(100);
        builder.Property(b => b.District).HasMaxLength(100);
        builder.Property(b => b.Ward).HasMaxLength(100);
        builder.Property(b => b.TaxCode).HasMaxLength(50);

        // Self-referencing hierarchy
        builder.HasOne(b => b.ParentBranch)
            .WithMany(b => b.Children)
            .HasForeignKey(b => b.ParentBranchId)
            .OnDelete(DeleteBehavior.Restrict);

        // Manager
        builder.HasOne(b => b.Manager)
            .WithMany()
            .HasForeignKey(b => b.ManagerId)
            .OnDelete(DeleteBehavior.SetNull);

        // Store
        builder.HasOne(b => b.Store)
            .WithMany()
            .HasForeignKey(b => b.StoreId)
            .OnDelete(DeleteBehavior.Cascade);

        // Unique code per store
        builder.HasIndex(b => new { b.StoreId, b.Code }).IsUnique();

        // Soft delete + tenant filters are applied centrally in ZKTecoDbContext.OnModelCreating
    }
}

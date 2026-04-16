using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class DepartmentConfiguration : IEntityTypeConfiguration<Department>
{
    public void Configure(EntityTypeBuilder<Department> builder)
    {
        builder.HasKey(e => e.Id);

        // Required fields
        builder.Property(e => e.Code)
            .IsRequired()
            .HasMaxLength(20);

        builder.Property(e => e.Name)
            .IsRequired()
            .HasMaxLength(200);

        builder.Property(e => e.Description)
            .HasMaxLength(500);

        builder.Property(e => e.HierarchyPath)
            .HasMaxLength(500);

        // ==================== Indexes ====================
        // Unique index for Code within Store
        builder.HasIndex(e => new { e.StoreId, e.Code })
            .IsUnique()
            .HasDatabaseName("IX_Department_Store_Code");

        // Index for parent department queries
        builder.HasIndex(e => e.ParentDepartmentId)
            .HasDatabaseName("IX_Department_ParentId");

        // Index for store queries
        builder.HasIndex(e => e.StoreId)
            .HasDatabaseName("IX_Department_StoreId");

        // Index for active departments
        builder.HasIndex(e => e.IsActive)
            .HasDatabaseName("IX_Department_IsActive");

        // Index for hierarchy path (để query nhanh các phòng ban con)
        builder.HasIndex(e => e.HierarchyPath)
            .HasDatabaseName("IX_Department_HierarchyPath");

        // Composite index for level + sort order (for tree display)
        builder.HasIndex(e => new { e.Level, e.SortOrder })
            .HasDatabaseName("IX_Department_Level_SortOrder");

        // ==================== Relationships ====================
        // Self-referencing relationship for hierarchy
        builder.HasOne(d => d.ParentDepartment)
            .WithMany(d => d.Children)
            .HasForeignKey(d => d.ParentDepartmentId)
            .OnDelete(DeleteBehavior.Restrict)
            .IsRequired(false);

        // Manager relationship
        builder.HasOne(d => d.Manager)
            .WithMany()
            .HasForeignKey(d => d.ManagerId)
            .OnDelete(DeleteBehavior.SetNull)
            .IsRequired(false);

        // Store relationship
        builder.HasOne(d => d.Store)
            .WithMany()
            .HasForeignKey(d => d.StoreId)
            .OnDelete(DeleteBehavior.Cascade)
            .IsRequired(false);

        // Employees relationship
        builder.HasMany(d => d.Employees)
            .WithOne()
            .HasForeignKey(e => e.DepartmentId)
            .OnDelete(DeleteBehavior.SetNull);

        // Default values
        builder.Property(e => e.Level).HasDefaultValue(0);
        builder.Property(e => e.SortOrder).HasDefaultValue(0);
        builder.Property(e => e.DirectEmployeeCount).HasDefaultValue(0);
        builder.Property(e => e.TotalEmployeeCount).HasDefaultValue(0);
        builder.Property(e => e.IsActive).HasDefaultValue(true);
    }
}

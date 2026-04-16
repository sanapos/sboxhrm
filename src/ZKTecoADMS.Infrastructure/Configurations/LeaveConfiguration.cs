using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.ChangeTracking;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class LeaveConfiguration : IEntityTypeConfiguration<Leave>
{
    public void Configure(EntityTypeBuilder<Leave> builder)
    {
        builder.HasKey(l => l.Id);
        
        builder.HasIndex(l => l.EmployeeUserId);
        builder.HasIndex(l => l.ShiftId);
        
        // Relationship: ApplicationUser -> RequestedLeaves
        builder.HasOne(l => l.EmployeeUser)
            .WithMany(u => u.RequestedLeaves)
            .HasForeignKey(l => l.EmployeeUserId)
            .OnDelete(DeleteBehavior.Cascade);
        
        // Relationship: Manager -> ManagedLeaves
        builder.HasOne(l => l.Manager)
            .WithMany(u => u.ManagedLeaves)
            .HasForeignKey(l => l.ManagerId)
            .OnDelete(DeleteBehavior.Restrict);

        // ShiftId stores ShiftTemplate ID for reference - no FK to Shift table
        builder.Property(l => l.ShiftId);
        builder.Ignore(l => l.Shift);

        // ShiftIds - explicitly configure column type and ValueComparer for proper change tracking
        builder.Property(l => l.ShiftIds)
            .HasColumnType("uuid[]");
        builder.Property(l => l.ShiftIds)
            .Metadata.SetValueComparer(new ValueComparer<List<Guid>>(
                (c1, c2) => c1 != null && c2 != null && c1.SequenceEqual(c2),
                c => c.Aggregate(0, (a, v) => HashCode.Combine(a, v.GetHashCode())),
                c => c.ToList()));

        // Composite index for report date-range queries
        builder.HasIndex(l => new { l.StoreId, l.StartDate, l.EndDate })
            .HasDatabaseName("IX_Leaves_Store_Dates");
    }
}

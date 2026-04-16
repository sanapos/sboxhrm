using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class ShiftSwapRequestConfiguration : IEntityTypeConfiguration<ShiftSwapRequest>
{
    public void Configure(EntityTypeBuilder<ShiftSwapRequest> builder)
    {
        builder.HasKey(e => e.Id);

        builder.Property(e => e.Reason)
            .HasMaxLength(500);

        builder.Property(e => e.RejectionReason)
            .HasMaxLength(500);

        builder.Property(e => e.Note)
            .HasMaxLength(500);

        // ==================== Indexes ====================
        builder.HasIndex(e => e.StoreId)
            .HasDatabaseName("IX_ShiftSwapRequest_StoreId");

        builder.HasIndex(e => e.RequesterUserId)
            .HasDatabaseName("IX_ShiftSwapRequest_RequesterId");

        builder.HasIndex(e => e.TargetUserId)
            .HasDatabaseName("IX_ShiftSwapRequest_TargetId");

        builder.HasIndex(e => e.Status)
            .HasDatabaseName("IX_ShiftSwapRequest_Status");

        builder.HasIndex(e => new { e.RequesterDate, e.TargetDate })
            .HasDatabaseName("IX_ShiftSwapRequest_Dates");

        builder.HasIndex(e => e.IsActive)
            .HasDatabaseName("IX_ShiftSwapRequest_IsActive");

        // ==================== Relationships ====================
        builder.HasOne(e => e.Store)
            .WithMany()
            .HasForeignKey(e => e.StoreId)
            .OnDelete(DeleteBehavior.Cascade);

        builder.HasOne(e => e.RequesterUser)
            .WithMany()
            .HasForeignKey(e => e.RequesterUserId)
            .OnDelete(DeleteBehavior.Restrict);

        builder.HasOne(e => e.TargetUser)
            .WithMany()
            .HasForeignKey(e => e.TargetUserId)
            .OnDelete(DeleteBehavior.Restrict);

        builder.HasOne(e => e.RequesterShift)
            .WithMany()
            .HasForeignKey(e => e.RequesterShiftId)
            .OnDelete(DeleteBehavior.Restrict);

        builder.HasOne(e => e.TargetShift)
            .WithMany()
            .HasForeignKey(e => e.TargetShiftId)
            .OnDelete(DeleteBehavior.Restrict);

        builder.HasOne(e => e.ApprovedByManager)
            .WithMany()
            .HasForeignKey(e => e.ApprovedByManagerId)
            .OnDelete(DeleteBehavior.SetNull)
            .IsRequired(false);

        // Default values
        builder.Property(e => e.Status).HasDefaultValue(ShiftSwapStatus.Pending);
        builder.Property(e => e.TargetAccepted).HasDefaultValue(false);
        builder.Property(e => e.IsActive).HasDefaultValue(true);
    }
}

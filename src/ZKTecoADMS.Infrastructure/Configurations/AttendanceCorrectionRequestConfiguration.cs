using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class AttendanceCorrectionRequestConfiguration : IEntityTypeConfiguration<AttendanceCorrectionRequest>
{
    public void Configure(EntityTypeBuilder<AttendanceCorrectionRequest> builder)
    {
        builder.HasKey(acr => acr.Id);

        builder.Property(acr => acr.Reason)
            .IsRequired()
            .HasMaxLength(1000);

        builder.Property(acr => acr.Action)
            .HasConversion<int>();

        builder.Property(acr => acr.Status)
            .HasConversion<int>();

        builder.Property(acr => acr.ApproverNote)
            .HasMaxLength(500);

        builder.Property(acr => acr.OldDevice)
            .HasMaxLength(100);

        builder.Property(acr => acr.OldType)
            .HasMaxLength(50);

        // Indexes
        builder.HasIndex(acr => acr.EmployeeUserId)
            .HasDatabaseName("IX_AttendanceCorrectionRequests_EmployeeUserId");

        builder.HasIndex(acr => acr.Status)
            .HasDatabaseName("IX_AttendanceCorrectionRequests_Status");

        builder.HasIndex(acr => acr.OldDate)
            .HasDatabaseName("IX_AttendanceCorrectionRequests_OldDate");

        builder.HasIndex(acr => acr.NewDate)
            .HasDatabaseName("IX_AttendanceCorrectionRequests_NewDate");
    }
}

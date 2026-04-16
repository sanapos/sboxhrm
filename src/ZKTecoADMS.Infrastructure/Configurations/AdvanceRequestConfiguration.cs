using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class AdvanceRequestConfiguration : IEntityTypeConfiguration<AdvanceRequest>
{
    public void Configure(EntityTypeBuilder<AdvanceRequest> builder)
    {
        builder.HasKey(ar => ar.Id);

        builder.Property(ar => ar.Amount)
            .HasPrecision(18, 2)
            .IsRequired();

        builder.Property(ar => ar.Reason)
            .IsRequired()
            .HasMaxLength(1000);

        builder.Property(ar => ar.Status)
            .HasConversion<int>();

        builder.Property(ar => ar.RejectionReason)
            .HasMaxLength(500);

        builder.Property(ar => ar.Note)
            .HasMaxLength(500);

        // Indexes
        builder.HasIndex(ar => ar.EmployeeUserId)
            .HasDatabaseName("IX_AdvanceRequests_EmployeeUserId");

        builder.HasIndex(ar => ar.Status)
            .HasDatabaseName("IX_AdvanceRequests_Status");

        builder.HasIndex(ar => ar.RequestDate)
            .HasDatabaseName("IX_AdvanceRequests_RequestDate");
    }
}

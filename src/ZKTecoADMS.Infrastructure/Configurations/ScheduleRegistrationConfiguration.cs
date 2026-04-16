using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class ScheduleRegistrationConfiguration : IEntityTypeConfiguration<ScheduleRegistration>
{
    public void Configure(EntityTypeBuilder<ScheduleRegistration> builder)
    {
        builder.HasKey(sr => sr.Id);

        builder.Property(sr => sr.Note)
            .HasMaxLength(500);

        builder.Property(sr => sr.Status)
            .HasConversion<int>();

        builder.Property(sr => sr.RejectionReason)
            .HasMaxLength(500);

        // Map EmployeeUserId property to EmployeeId column in DB
        builder.Property(sr => sr.EmployeeUserId)
            .HasColumnName("EmployeeId");

        // Relationship with Employee
        builder.HasOne(sr => sr.Employee)
            .WithMany()
            .HasForeignKey(sr => sr.EmployeeUserId)
            .OnDelete(DeleteBehavior.Restrict);

        // Relationship with ShiftTemplate
        builder.HasOne(sr => sr.Shift)
            .WithMany()
            .HasForeignKey(sr => sr.ShiftId)
            .OnDelete(DeleteBehavior.Restrict);

        // Indexes
        builder.HasIndex(sr => sr.EmployeeUserId)
            .HasDatabaseName("IX_ScheduleRegistrations_EmployeeUserId");

        builder.HasIndex(sr => sr.Status)
            .HasDatabaseName("IX_ScheduleRegistrations_Status");

        builder.HasIndex(sr => sr.Date)
            .HasDatabaseName("IX_ScheduleRegistrations_Date");
    }
}

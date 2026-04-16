using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class WorkScheduleConfiguration : IEntityTypeConfiguration<WorkSchedule>
{
    public void Configure(EntityTypeBuilder<WorkSchedule> builder)
    {
        builder.HasKey(ws => ws.Id);

        builder.Property(ws => ws.Note)
            .HasMaxLength(500);

        // Map EmployeeUserId property to EmployeeId column in DB
        builder.Property(ws => ws.EmployeeUserId)
            .HasColumnName("EmployeeId");

        // Relationship with Employee
        builder.HasOne(ws => ws.Employee)
            .WithMany()
            .HasForeignKey(ws => ws.EmployeeUserId)
            .OnDelete(DeleteBehavior.Restrict);

        // Relationship with ShiftTemplate
        builder.HasOne(ws => ws.Shift)
            .WithMany()
            .HasForeignKey(ws => ws.ShiftId)
            .OnDelete(DeleteBehavior.Restrict);

        // Indexes
        builder.HasIndex(ws => ws.EmployeeUserId)
            .HasDatabaseName("IX_WorkSchedules_EmployeeUserId");

        builder.HasIndex(ws => ws.Date)
            .HasDatabaseName("IX_WorkSchedules_Date");

        builder.HasIndex(ws => ws.ShiftId)
            .HasDatabaseName("IX_WorkSchedules_ShiftId");

        builder.HasIndex(ws => new { ws.EmployeeUserId, ws.Date })
            .IsUnique()
            .HasDatabaseName("IX_WorkSchedules_Employee_Date");
    }
}

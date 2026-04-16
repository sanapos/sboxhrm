using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class AttendanceConfiguration : IEntityTypeConfiguration<Attendance>
{
    public void Configure(EntityTypeBuilder<Attendance> builder)
    {
        builder.HasKey(e => e.Id);
        builder.HasIndex(e => e.DeviceId);
        builder.HasIndex(e => e.EmployeeId);
        builder.HasIndex(e => e.PIN);

        // Composite indexes for query performance
        builder.HasIndex(e => new { e.EmployeeId, e.AttendanceTime })
            .HasDatabaseName("IX_Attendance_Employee_Time");

        builder.HasIndex(e => new { e.DeviceId, e.AttendanceTime })
            .HasDatabaseName("IX_Attendance_Device_Time");

        // Reports query by PIN + AttendanceTime extensively
        builder.HasIndex(e => new { e.PIN, e.AttendanceTime })
            .HasDatabaseName("IX_Attendance_PIN_Time");

        builder.HasOne(e => e.Device)
            .WithMany(d => d.AttendanceLogs)
            .HasForeignKey(e => e.DeviceId)
            .OnDelete(DeleteBehavior.Cascade);

        builder.HasOne(e => e.Employee)
            .WithMany(u => u.AttendanceLogs)
            .HasForeignKey(e => e.EmployeeId)
            .OnDelete(DeleteBehavior.Cascade);

    }
}
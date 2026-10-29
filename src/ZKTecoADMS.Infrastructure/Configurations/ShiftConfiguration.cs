using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class ShiftConfiguration : IEntityTypeConfiguration<Shift>
{
    public void Configure(EntityTypeBuilder<Shift> builder)
    {
        builder.HasKey(s => s.Id);
        
        builder.HasIndex(s => s.EmployeeUserId);
        
        // Relationship: ApplicationUser -> RequestedShifts
        builder.HasOne(s => s.EmployeeUser)
            .WithMany(u => u.RequestedShifts)
            .HasForeignKey(s => s.EmployeeUserId)
            .OnDelete(DeleteBehavior.Cascade);

        // Relationship: Shift -> CheckInAttendance
        builder.HasOne(s => s.CheckInAttendance)
            .WithMany()
            .HasForeignKey(s => s.CheckInAttendanceId)
            .OnDelete(DeleteBehavior.SetNull);

        builder.HasOne(s => s.CheckOutAttendance)
            .WithMany()
            .HasForeignKey(s => s.CheckOutAttendanceId)
            .OnDelete(DeleteBehavior.SetNull);

        // Leave.ShiftId lưu id CA MẪU (ShiftTemplate), không phải Shift — xem LeaveConfiguration.
        // Để điều hướng này thì EF tự suy ra quan hệ 1-1 Shift↔Leave và sinh FK Leaves→Shifts
        // (migration AddPenaltyTickets), làm mọi đơn nghỉ mới lỗi 23503 khi lưu.
        builder.Ignore(s => s.Leave);
    }
}

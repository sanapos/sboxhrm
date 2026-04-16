using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class PenaltyTicketConfiguration : IEntityTypeConfiguration<PenaltyTicket>
{
    public void Configure(EntityTypeBuilder<PenaltyTicket> builder)
    {
        builder.HasKey(pt => pt.Id);

        builder.Property(pt => pt.Amount).HasPrecision(18, 2);

        builder.HasIndex(pt => pt.TicketCode).IsUnique();
        builder.HasIndex(pt => new { pt.StoreId, pt.Status, pt.ViolationDate });
        builder.HasIndex(pt => new { pt.EmployeeId, pt.ViolationDate });

        builder.HasOne(pt => pt.Employee)
            .WithMany()
            .HasForeignKey(pt => pt.EmployeeId)
            .OnDelete(DeleteBehavior.Restrict);

        builder.HasOne(pt => pt.ProcessedBy)
            .WithMany()
            .HasForeignKey(pt => pt.ProcessedById)
            .OnDelete(DeleteBehavior.SetNull);

        builder.HasOne(pt => pt.CashTransaction)
            .WithMany()
            .HasForeignKey(pt => pt.CashTransactionId)
            .OnDelete(DeleteBehavior.SetNull);

        builder.HasOne(pt => pt.Shift)
            .WithMany()
            .HasForeignKey(pt => pt.ShiftId)
            .OnDelete(DeleteBehavior.SetNull);

        builder.HasOne(pt => pt.Attendance)
            .WithMany()
            .HasForeignKey(pt => pt.AttendanceId)
            .OnDelete(DeleteBehavior.SetNull);
    }
}

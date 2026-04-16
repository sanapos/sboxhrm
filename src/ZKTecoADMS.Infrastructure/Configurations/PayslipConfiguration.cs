using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class PayslipConfiguration : IEntityTypeConfiguration<Payslip>
{
    public void Configure(EntityTypeBuilder<Payslip> builder)
    {
        builder.HasKey(p => p.Id);

        builder.Property(p => p.Year)
            .IsRequired();

        builder.Property(p => p.Month)
            .IsRequired();

        builder.Property(p => p.PeriodStart)
            .IsRequired();

        builder.Property(p => p.PeriodEnd)
            .IsRequired();

        builder.Property(p => p.RegularWorkUnits)
            .HasPrecision(18, 2)
            .IsRequired();

        builder.Property(p => p.OvertimeUnits)
            .HasPrecision(18, 2);

        builder.Property(p => p.HolidayUnits)
            .HasPrecision(18, 2);

        builder.Property(p => p.NightShiftUnits)
            .HasPrecision(18, 2);

        builder.Property(p => p.BaseSalary)
            .HasPrecision(18, 2)
            .IsRequired();

        builder.Property(p => p.OvertimePay)
            .HasPrecision(18, 2);

        builder.Property(p => p.HolidayPay)
            .HasPrecision(18, 2);

        builder.Property(p => p.NightShiftPay)
            .HasPrecision(18, 2);

        builder.Property(p => p.Bonus)
            .HasPrecision(18, 2);

        builder.Property(p => p.Deductions)
            .HasPrecision(18, 2);

        builder.Property(p => p.GrossSalary)
            .HasPrecision(18, 2)
            .IsRequired();

        builder.Property(p => p.NetSalary)
            .HasPrecision(18, 2)
            .IsRequired();

        builder.Property(p => p.Currency)
            .HasMaxLength(10)
            .IsRequired();

        builder.Property(p => p.Status)
            .IsRequired();

        builder.Property(p => p.Notes)
            .HasMaxLength(1000);

        // Relationships
        builder.HasOne(p => p.EmployeeUser)
            .WithMany()
            .HasForeignKey(p => p.EmployeeUserId)
            .OnDelete(DeleteBehavior.Restrict);

        builder.HasOne(p => p.SalaryProfile)
            .WithMany()
            .HasForeignKey(p => p.SalaryProfileId)
            .OnDelete(DeleteBehavior.Restrict);

        builder.HasOne(p => p.GeneratedByUser)
            .WithMany()
            .HasForeignKey(p => p.GeneratedByUserId)
            .OnDelete(DeleteBehavior.SetNull);

        builder.HasOne(p => p.ApprovedByUser)
            .WithMany()
            .HasForeignKey(p => p.ApprovedByUserId)
            .OnDelete(DeleteBehavior.SetNull);

        // Index for faster lookups
        builder.HasIndex(p => new { p.EmployeeUserId, p.Year, p.Month })
            .IsUnique();

        builder.HasIndex(p => new { p.Year, p.Month });
        builder.HasIndex(p => p.Status);
    }
}

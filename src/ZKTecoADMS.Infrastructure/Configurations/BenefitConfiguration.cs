using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class BenefitConfiguration : IEntityTypeConfiguration<Benefit>
{
    public void Configure(EntityTypeBuilder<Benefit> builder)
    {
        builder.ToTable("SalaryProfiles");

        builder.HasKey(x => x.Id);

        builder.Property(x => x.Name)
            .IsRequired()
            .HasMaxLength(200);

        builder.Property(x => x.Description)
            .HasMaxLength(500);

        builder.Property(x => x.RateType)
            .IsRequired()
            .HasConversion<int>();

        builder.Property(x => x.Rate)
            .IsRequired()
            .HasColumnType("decimal(18,2)");

        builder.Property(x => x.Currency)
            .IsRequired()
            .HasMaxLength(10);

        builder.Property(x => x.OvertimeMultiplier)
            .HasColumnType("decimal(5,2)");

        builder.Property(x => x.HolidayMultiplier)
            .HasColumnType("decimal(5,2)");

        builder.Property(x => x.NightShiftMultiplier)
            .HasColumnType("decimal(5,2)");

        // Leave & Attendance Rules
        builder.Property(x => x.PaidLeaveDays)
            .HasColumnType("decimal(5,2)");

        builder.Property(x => x.UnpaidLeaveDays)
            .HasColumnType("decimal(5,2)");

        // Allowances
        builder.Property(x => x.MealAllowance)
            .HasColumnType("decimal(18,2)");

        builder.Property(x => x.TransportAllowance)
            .HasColumnType("decimal(18,2)");

        builder.Property(x => x.HousingAllowance)
            .HasColumnType("decimal(18,2)");

        builder.Property(x => x.ResponsibilityAllowance)
            .HasColumnType("decimal(18,2)");

        builder.Property(x => x.AttendanceBonus)
            .HasColumnType("decimal(18,2)");

        builder.Property(x => x.PhoneSkillShiftAllowance)
            .HasColumnType("decimal(18,2)");

        // Overtime Configuration
        builder.Property(x => x.OTRateWeekday)
            .HasColumnType("decimal(5,2)");

        builder.Property(x => x.OTRateWeekend)
            .HasColumnType("decimal(5,2)");

        builder.Property(x => x.OTRateHoliday)
            .HasColumnType("decimal(5,2)");

        builder.Property(x => x.NightShiftRate)
            .HasColumnType("decimal(5,2)");

        // Health Insurance
        builder.Property(x => x.HealthInsuranceRate)
            .HasColumnType("decimal(5,4)");

        // Configure relationship with EmployeeBenefits
        builder.HasMany(b => b.EmployeeBenefits)
            .WithOne(eb => eb.Benefit)
            .HasForeignKey(eb => eb.BenefitId)
            .OnDelete(DeleteBehavior.Restrict);

        // Configure many-to-many relationship with Employees through EmployeeBenefit
        builder.HasMany(b => b.Employees)
            .WithMany(e => e.Benefits)
            .UsingEntity<EmployeeBenefit>(
                j => j.HasOne(eb => eb.Employee)
                      .WithMany(e => e.EmployeeBenefits)
                      .HasForeignKey(eb => eb.EmployeeId),
                j => j.HasOne(eb => eb.Benefit)
                      .WithMany(b => b.EmployeeBenefits)
                      .HasForeignKey(eb => eb.BenefitId)
            );

        builder.HasIndex(x => x.Name);
        builder.HasIndex(x => x.RateType);
    }
}

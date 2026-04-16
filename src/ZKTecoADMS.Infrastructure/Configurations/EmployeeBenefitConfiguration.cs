using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class EmployeeBenefitConfiguration : IEntityTypeConfiguration<EmployeeBenefit>
{
    public void Configure(EntityTypeBuilder<EmployeeBenefit> builder)
    {
        builder.HasKey(x => x.Id);

        builder.Property(x => x.EffectiveDate)
            .IsRequired();

        builder.Property(x => x.EndDate)
            .IsRequired(false)
            .HasDefaultValue(null);

        builder.Property(x => x.Notes)
            .HasMaxLength(500);

        builder.Property(x => x.BalancedPaidLeaveDays)
            .HasColumnType("decimal(5,2)");

        builder.Property(x => x.BalancedUnpaidLeaveDays)
            .HasColumnType("decimal(5,2)");

        // Configure relationship with Employee (already configured on Employee side)
        builder.HasOne(x => x.Employee)
            .WithMany(e => e.EmployeeBenefits)
            .HasForeignKey(x => x.EmployeeId)
            .OnDelete(DeleteBehavior.Cascade);

        // Configure relationship with Benefit
        builder.HasOne(x => x.Benefit)
            .WithMany(b => b.EmployeeBenefits)
            .HasForeignKey(x => x.BenefitId)
            .OnDelete(DeleteBehavior.Restrict);

    }
}

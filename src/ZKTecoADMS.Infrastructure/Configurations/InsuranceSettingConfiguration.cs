using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class InsuranceSettingConfiguration : IEntityTypeConfiguration<InsuranceSetting>
{
    public void Configure(EntityTypeBuilder<InsuranceSetting> builder)
    {
        builder.HasKey(ins => ins.Id);

        // Base salary
        builder.Property(ins => ins.BaseSalary).HasPrecision(18, 2);
        builder.Property(ins => ins.MinSalaryRegion1).HasPrecision(18, 2);
        builder.Property(ins => ins.MinSalaryRegion2).HasPrecision(18, 2);
        builder.Property(ins => ins.MinSalaryRegion3).HasPrecision(18, 2);
        builder.Property(ins => ins.MinSalaryRegion4).HasPrecision(18, 2);
        builder.Property(ins => ins.MaxInsuranceSalary).HasPrecision(18, 2);

        // BHXH rates
        builder.Property(ins => ins.BhxhEmployeeRate).HasPrecision(5, 2);
        builder.Property(ins => ins.BhxhEmployerRate).HasPrecision(5, 2);

        // BHYT rates
        builder.Property(ins => ins.BhytEmployeeRate).HasPrecision(5, 2);
        builder.Property(ins => ins.BhytEmployerRate).HasPrecision(5, 2);

        // BHTN rates
        builder.Property(ins => ins.BhtnEmployeeRate).HasPrecision(5, 2);
        builder.Property(ins => ins.BhtnEmployerRate).HasPrecision(5, 2);

        // Union fees
        builder.Property(ins => ins.UnionFeeEmployeeRate).HasPrecision(5, 2);
        builder.Property(ins => ins.UnionFeeEmployerRate).HasPrecision(5, 2);

        // Indexes
        builder.HasIndex(ins => ins.EffectiveYear)
            .HasDatabaseName("IX_InsuranceSettings_EffectiveYear");
    }
}

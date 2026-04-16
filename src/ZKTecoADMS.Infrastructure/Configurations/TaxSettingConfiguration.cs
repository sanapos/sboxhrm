using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class TaxSettingConfiguration : IEntityTypeConfiguration<TaxSetting>
{
    public void Configure(EntityTypeBuilder<TaxSetting> builder)
    {
        builder.HasKey(ts => ts.Id);

        // Personal deductions
        builder.Property(ts => ts.PersonalDeduction).HasPrecision(18, 2);
        builder.Property(ts => ts.DependentDeduction).HasPrecision(18, 2);

        // Tax brackets
        builder.Property(ts => ts.TaxBracket1Max).HasPrecision(18, 2);
        builder.Property(ts => ts.TaxBracket2Max).HasPrecision(18, 2);
        builder.Property(ts => ts.TaxBracket3Max).HasPrecision(18, 2);
        builder.Property(ts => ts.TaxBracket4Max).HasPrecision(18, 2);
        builder.Property(ts => ts.TaxBracket5Max).HasPrecision(18, 2);
        builder.Property(ts => ts.TaxBracket6Max).HasPrecision(18, 2);

        // Tax rates
        builder.Property(ts => ts.TaxRate1).HasPrecision(5, 2);
        builder.Property(ts => ts.TaxRate2).HasPrecision(5, 2);
        builder.Property(ts => ts.TaxRate3).HasPrecision(5, 2);
        builder.Property(ts => ts.TaxRate4).HasPrecision(5, 2);
        builder.Property(ts => ts.TaxRate5).HasPrecision(5, 2);
        builder.Property(ts => ts.TaxRate6).HasPrecision(5, 2);
        builder.Property(ts => ts.TaxRate7).HasPrecision(5, 2);

        // Indexes
        builder.HasIndex(ts => ts.EffectiveYear)
            .HasDatabaseName("IX_TaxSettings_EffectiveYear");
    }
}

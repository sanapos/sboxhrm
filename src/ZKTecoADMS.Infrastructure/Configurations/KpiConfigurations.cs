using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class KpiConfigConfiguration : IEntityTypeConfiguration<KpiConfig>
{
    public void Configure(EntityTypeBuilder<KpiConfig> builder)
    {
        builder.HasKey(e => e.Id);

        builder.Property(e => e.Code).IsRequired().HasMaxLength(50);
        builder.Property(e => e.Name).IsRequired().HasMaxLength(200);
        builder.Property(e => e.Description).HasMaxLength(1000);
        builder.Property(e => e.Unit).HasMaxLength(50);
        builder.Property(e => e.GoogleSheetColumnName).HasMaxLength(100);

        builder.Property(e => e.Weight).HasPrecision(18, 2);
        builder.Property(e => e.TargetValue).HasPrecision(18, 2);
        builder.Property(e => e.MinValue).HasPrecision(18, 2);
        builder.Property(e => e.MaxValue).HasPrecision(18, 2);

        builder.Property(e => e.Type).HasConversion<int>();
        builder.Property(e => e.Frequency).HasConversion<int>();

        builder.HasOne(e => e.Store)
            .WithMany()
            .HasForeignKey(e => e.StoreId)
            .OnDelete(DeleteBehavior.SetNull);

        builder.HasIndex(e => new { e.Code, e.StoreId })
            .IsUnique()
            .HasDatabaseName("IX_KpiConfig_Code_StoreId");
    }
}

public class KpiPeriodConfiguration : IEntityTypeConfiguration<KpiPeriod>
{
    public void Configure(EntityTypeBuilder<KpiPeriod> builder)
    {
        builder.HasKey(e => e.Id);

        builder.Property(e => e.Name).IsRequired().HasMaxLength(100);
        builder.Property(e => e.GoogleSpreadsheetId).HasMaxLength(200);
        builder.Property(e => e.GoogleSheetName).HasMaxLength(100);
        builder.Property(e => e.Notes).HasMaxLength(1000);

        builder.Property(e => e.Frequency).HasConversion<int>();
        builder.Property(e => e.Status).HasConversion<int>();

        builder.HasOne(e => e.Store)
            .WithMany()
            .HasForeignKey(e => e.StoreId)
            .OnDelete(DeleteBehavior.SetNull);

        builder.HasIndex(e => new { e.Year, e.Month, e.StoreId })
            .HasDatabaseName("IX_KpiPeriod_Year_Month_StoreId");
    }
}

public class KpiResultConfiguration : IEntityTypeConfiguration<KpiResult>
{
    public void Configure(EntityTypeBuilder<KpiResult> builder)
    {
        builder.HasKey(e => e.Id);

        builder.Property(e => e.ActualValue).HasPrecision(18, 2);
        builder.Property(e => e.TargetValue).HasPrecision(18, 2);
        builder.Property(e => e.CompletionRate).HasPrecision(18, 2);
        builder.Property(e => e.WeightedScore).HasPrecision(18, 4);
        builder.Property(e => e.Notes).HasMaxLength(500);
        builder.Property(e => e.Source).HasMaxLength(50);

        builder.HasOne(e => e.Employee)
            .WithMany()
            .HasForeignKey(e => e.EmployeeId)
            .OnDelete(DeleteBehavior.Restrict);

        builder.HasOne(e => e.KpiConfig)
            .WithMany(c => c.KpiResults)
            .HasForeignKey(e => e.KpiConfigId)
            .OnDelete(DeleteBehavior.Restrict);

        builder.HasOne(e => e.KpiPeriod)
            .WithMany(p => p.KpiResults)
            .HasForeignKey(e => e.KpiPeriodId)
            .OnDelete(DeleteBehavior.Restrict);

        builder.HasOne(e => e.Store)
            .WithMany()
            .HasForeignKey(e => e.StoreId)
            .OnDelete(DeleteBehavior.SetNull);

        builder.HasIndex(e => new { e.EmployeeId, e.KpiConfigId, e.KpiPeriodId })
            .IsUnique()
            .HasDatabaseName("IX_KpiResult_Employee_Config_Period");
    }
}

public class KpiSalaryConfiguration : IEntityTypeConfiguration<KpiSalary>
{
    public void Configure(EntityTypeBuilder<KpiSalary> builder)
    {
        builder.HasKey(e => e.Id);

        builder.Property(e => e.BaseSalary).HasPrecision(18, 2);
        builder.Property(e => e.TotalKpiScore).HasPrecision(18, 2);
        builder.Property(e => e.KpiBonusRate).HasPrecision(18, 2);
        builder.Property(e => e.KpiBonusAmount).HasPrecision(18, 2);
        builder.Property(e => e.Allowances).HasPrecision(18, 2);
        builder.Property(e => e.OtherBonus).HasPrecision(18, 2);
        builder.Property(e => e.Deductions).HasPrecision(18, 2);
        builder.Property(e => e.GrossIncome).HasPrecision(18, 2);
        builder.Property(e => e.NetIncome).HasPrecision(18, 2);
        builder.Property(e => e.Currency).HasMaxLength(10);
        builder.Property(e => e.Notes).HasMaxLength(1000);

        builder.HasOne(e => e.Employee)
            .WithMany()
            .HasForeignKey(e => e.EmployeeId)
            .OnDelete(DeleteBehavior.Restrict);

        builder.HasOne(e => e.KpiPeriod)
            .WithMany(p => p.KpiSalaries)
            .HasForeignKey(e => e.KpiPeriodId)
            .OnDelete(DeleteBehavior.Restrict);

        builder.HasOne(e => e.ApprovedByUser)
            .WithMany()
            .HasForeignKey(e => e.ApprovedByUserId)
            .OnDelete(DeleteBehavior.SetNull);

        builder.HasOne(e => e.Store)
            .WithMany()
            .HasForeignKey(e => e.StoreId)
            .OnDelete(DeleteBehavior.SetNull);

        builder.HasIndex(e => new { e.EmployeeId, e.KpiPeriodId })
            .IsUnique()
            .HasDatabaseName("IX_KpiSalary_Employee_Period");
    }
}

public class KpiBonusRuleConfiguration : IEntityTypeConfiguration<KpiBonusRule>
{
    public void Configure(EntityTypeBuilder<KpiBonusRule> builder)
    {
        builder.HasKey(e => e.Id);

        builder.Property(e => e.Name).IsRequired().HasMaxLength(200);
        builder.Property(e => e.Description).HasMaxLength(500);
        builder.Property(e => e.MinScore).HasPrecision(18, 2);
        builder.Property(e => e.MaxScore).HasPrecision(18, 2);
        builder.Property(e => e.BonusRate).HasPrecision(18, 2);

        builder.HasOne(e => e.Store)
            .WithMany()
            .HasForeignKey(e => e.StoreId)
            .OnDelete(DeleteBehavior.SetNull);

        builder.HasIndex(e => new { e.StoreId, e.SortOrder })
            .HasDatabaseName("IX_KpiBonusRule_Store_SortOrder");
    }
}

public class KpiEmployeeTargetConfiguration : IEntityTypeConfiguration<KpiEmployeeTarget>
{
    public void Configure(EntityTypeBuilder<KpiEmployeeTarget> builder)
    {
        builder.HasIndex(e => new { e.EmployeeId, e.KpiPeriodId })
            .HasDatabaseName("IX_KpiEmployeeTarget_Employee_Period");

        builder.HasIndex(e => e.KpiPeriodId)
            .HasDatabaseName("IX_KpiEmployeeTarget_PeriodId");
    }
}

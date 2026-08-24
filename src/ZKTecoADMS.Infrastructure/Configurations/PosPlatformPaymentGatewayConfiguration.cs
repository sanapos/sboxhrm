using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class PosPlatformNotificationCreditConfiguration : IEntityTypeConfiguration<PosPlatformNotificationCredit>
{
    public void Configure(EntityTypeBuilder<PosPlatformNotificationCredit> builder)
    {
        builder.ToTable("PosPlatformNotificationCredits");
        builder.HasKey(x => x.Id);
        builder.Property(x => x.LastCostPerCredit).HasPrecision(18, 2);
    }
}

public class PosPlatformNotificationCreditLedgerConfiguration
    : IEntityTypeConfiguration<PosPlatformNotificationCreditLedger>
{
    public void Configure(EntityTypeBuilder<PosPlatformNotificationCreditLedger> builder)
    {
        builder.ToTable("PosPlatformNotificationCreditLedgers");
        builder.HasKey(x => x.Id);
        builder.Property(x => x.Note).HasMaxLength(500);
        builder.HasIndex(x => x.CreatedAt);
    }
}

public class PosPlatformTingeeSettingConfiguration : IEntityTypeConfiguration<PosPlatformTingeeSetting>
{
    public void Configure(EntityTypeBuilder<PosPlatformTingeeSetting> builder)
    {
        builder.ToTable("PosPlatformTingeeSettings");
        builder.HasKey(x => x.Id);
        builder.Property(x => x.TingeeClientId).HasMaxLength(100);
        builder.Property(x => x.TingeeSecretKey).HasMaxLength(300);
        builder.Property(x => x.TingeeWebhookSecret).HasMaxLength(300);
        builder.Property(x => x.ApiEnvironment).HasMaxLength(20);
        builder.Property(x => x.ApiBaseUrlOverride).HasMaxLength(200);
        builder.Property(x => x.DefaultVaAccountNumber).HasMaxLength(100);
    }
}

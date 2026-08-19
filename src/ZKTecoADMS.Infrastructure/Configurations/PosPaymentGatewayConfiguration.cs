using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class PosPaymentGatewaySettingConfiguration : IEntityTypeConfiguration<PosPaymentGatewaySetting>
{
    public void Configure(EntityTypeBuilder<PosPaymentGatewaySetting> builder)
    {
        builder.ToTable("PosPaymentGatewaySettings");
        builder.HasKey(x => x.Id);
        builder.HasIndex(x => x.StoreId).IsUnique();
        builder.Property(x => x.TingeeClientId).HasMaxLength(100);
        builder.Property(x => x.TingeeSecretKey).HasMaxLength(300);
        builder.Property(x => x.TingeeVaAccountNumber).HasMaxLength(100);
        builder.Property(x => x.TingeeMerchantId).HasMaxLength(50);
        builder.Property(x => x.TingeeWebhookSecret).HasMaxLength(300);
        builder.Property(x => x.ExtraJson).HasMaxLength(4000);
        builder.HasOne(x => x.Store).WithMany().HasForeignKey(x => x.StoreId)
            .OnDelete(DeleteBehavior.Cascade);
    }
}

public class PosStoreNotificationCreditConfiguration : IEntityTypeConfiguration<PosStoreNotificationCredit>
{
    public void Configure(EntityTypeBuilder<PosStoreNotificationCredit> builder)
    {
        builder.ToTable("PosStoreNotificationCredits");
        builder.HasKey(x => x.Id);
        builder.HasIndex(x => x.StoreId).IsUnique();
        builder.HasOne(x => x.Store).WithMany().HasForeignKey(x => x.StoreId)
            .OnDelete(DeleteBehavior.Cascade);
    }
}

public class PosNotificationCreditPackageConfiguration : IEntityTypeConfiguration<PosNotificationCreditPackage>
{
    public void Configure(EntityTypeBuilder<PosNotificationCreditPackage> builder)
    {
        builder.ToTable("PosNotificationCreditPackages");
        builder.HasKey(x => x.Id);
        builder.Property(x => x.Name).HasMaxLength(120).IsRequired();
        builder.Property(x => x.Price).HasPrecision(18, 2);
        builder.Property(x => x.Description).HasMaxLength(500);
    }
}

public class PosNotificationCreditPurchaseConfiguration : IEntityTypeConfiguration<PosNotificationCreditPurchase>
{
    public void Configure(EntityTypeBuilder<PosNotificationCreditPurchase> builder)
    {
        builder.ToTable("PosNotificationCreditPurchases");
        builder.HasKey(x => x.Id);
        builder.Property(x => x.AmountPaid).HasPrecision(18, 2);
        builder.Property(x => x.ExternalPaymentRef).HasMaxLength(120);
        builder.Property(x => x.Note).HasMaxLength(500);
        builder.HasIndex(x => new { x.StoreId, x.Status });
        builder.HasOne(x => x.Store).WithMany().HasForeignKey(x => x.StoreId)
            .OnDelete(DeleteBehavior.Cascade);
        builder.HasOne(x => x.Package).WithMany().HasForeignKey(x => x.PackageId)
            .OnDelete(DeleteBehavior.SetNull);
    }
}

public class PosNotificationCreditLedgerConfiguration : IEntityTypeConfiguration<PosNotificationCreditLedger>
{
    public void Configure(EntityTypeBuilder<PosNotificationCreditLedger> builder)
    {
        builder.ToTable("PosNotificationCreditLedgers");
        builder.HasKey(x => x.Id);
        builder.Property(x => x.ProviderTransactionCode).HasMaxLength(120);
        builder.Property(x => x.Note).HasMaxLength(500);
        builder.HasIndex(x => new { x.StoreId, x.CreatedAt });
        builder.HasIndex(x => x.ProviderTransactionCode)
            .IsUnique()
            .HasFilter("\"ProviderTransactionCode\" IS NOT NULL AND \"Deleted\" IS NULL");
        builder.HasOne(x => x.Store).WithMany().HasForeignKey(x => x.StoreId)
            .OnDelete(DeleteBehavior.Cascade);
    }
}

public class PosTransferPaymentIntentConfiguration : IEntityTypeConfiguration<PosTransferPaymentIntent>
{
    public void Configure(EntityTypeBuilder<PosTransferPaymentIntent> builder)
    {
        builder.ToTable("PosTransferPaymentIntents");
        builder.HasKey(x => x.Id);
        builder.Property(x => x.ExternalOrderId).HasMaxLength(100).IsRequired();
        builder.Property(x => x.OrderNo).HasMaxLength(40);
        builder.Property(x => x.AmountExpected).HasPrecision(18, 2);
        builder.Property(x => x.ProviderTransactionCode).HasMaxLength(120);
        builder.Property(x => x.TransferContent).HasMaxLength(500);
        builder.Property(x => x.TableName).HasMaxLength(200);
        builder.Property(x => x.RawWebhookJson).HasMaxLength(2000);
        builder.HasIndex(x => new { x.StoreId, x.Status, x.CreatedAt });
        builder.HasIndex(x => new { x.StoreId, x.ExternalOrderId });
        builder.HasIndex(x => x.ProviderTransactionCode)
            .HasFilter("\"ProviderTransactionCode\" IS NOT NULL AND \"Deleted\" IS NULL");
        builder.HasOne(x => x.Store).WithMany().HasForeignKey(x => x.StoreId)
            .OnDelete(DeleteBehavior.Cascade);
        builder.HasOne(x => x.SaleOrder).WithMany().HasForeignKey(x => x.SaleOrderId)
            .OnDelete(DeleteBehavior.SetNull);
    }
}

public class PosPaymentWebhookEventConfiguration : IEntityTypeConfiguration<PosPaymentWebhookEvent>
{
    public void Configure(EntityTypeBuilder<PosPaymentWebhookEvent> builder)
    {
        builder.ToTable("PosPaymentWebhookEvents");
        builder.HasKey(x => x.Id);
        builder.Property(x => x.ProviderTransactionCode).HasMaxLength(120);
        builder.Property(x => x.EventType).HasMaxLength(80);
        builder.Property(x => x.ResultCode).HasMaxLength(10);
        builder.Property(x => x.PayloadJson).HasMaxLength(8000);
        builder.HasIndex(x => new { x.Provider, x.ProviderTransactionCode });
        builder.HasIndex(x => x.ReceivedAt);
    }
}

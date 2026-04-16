using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class CashTransactionConfiguration : IEntityTypeConfiguration<CashTransaction>
{
    public void Configure(EntityTypeBuilder<CashTransaction> builder)
    {
        builder.ToTable("CashTransactions");
        
        builder.HasKey(x => x.Id);
        
        builder.Property(x => x.TransactionCode)
            .IsRequired()
            .HasMaxLength(50);
        
        builder.Property(x => x.Type)
            .IsRequired();
        
        builder.Property(x => x.Amount)
            .IsRequired()
            .HasPrecision(18, 2);
        
        builder.Property(x => x.TransactionDate)
            .IsRequired();
        
        builder.Property(x => x.Description)
            .IsRequired()
            .HasMaxLength(500);
        
        builder.Property(x => x.PaymentMethod)
            .IsRequired();
        
        builder.Property(x => x.Status)
            .IsRequired();
        
        builder.Property(x => x.ContactName)
            .HasMaxLength(200);
        
        builder.Property(x => x.ContactPhone)
            .HasMaxLength(20);
        
        builder.Property(x => x.PaymentReference)
            .HasMaxLength(100);
        
        builder.Property(x => x.ReceiptImageUrl)
            .HasMaxLength(500);
        
        builder.Property(x => x.VietQRUrl)
            .HasMaxLength(1000);
        
        builder.Property(x => x.InternalNote)
            .HasMaxLength(1000);
        
        builder.Property(x => x.Tags)
            .HasMaxLength(500);
        
        // Relationships
        builder.HasOne(x => x.Category)
            .WithMany(x => x.Transactions)
            .HasForeignKey(x => x.CategoryId)
            .OnDelete(DeleteBehavior.Restrict);
        
        builder.HasOne(x => x.BankAccount)
            .WithMany(x => x.Transactions)
            .HasForeignKey(x => x.BankAccountId)
            .OnDelete(DeleteBehavior.SetNull);
        
        builder.HasOne(x => x.CreatedByUser)
            .WithMany()
            .HasForeignKey(x => x.CreatedByUserId)
            .OnDelete(DeleteBehavior.Restrict);
        
        // Indexes
        builder.HasIndex(x => x.TransactionCode).IsUnique();
        builder.HasIndex(x => x.TransactionDate);
        builder.HasIndex(x => x.Type);
        builder.HasIndex(x => x.Status);
        builder.HasIndex(x => x.CategoryId);
        builder.HasIndex(x => x.CreatedByUserId);

        // Composite index for summary/report queries
        builder.HasIndex(x => new { x.StoreId, x.Status, x.TransactionDate })
            .HasDatabaseName("IX_CashTransactions_Store_Status_Date");
    }
}

public class TransactionCategoryConfiguration : IEntityTypeConfiguration<TransactionCategory>
{
    public void Configure(EntityTypeBuilder<TransactionCategory> builder)
    {
        builder.ToTable("TransactionCategories");
        
        builder.HasKey(x => x.Id);
        
        builder.Property(x => x.Name)
            .IsRequired()
            .HasMaxLength(100);
        
        builder.Property(x => x.Description)
            .HasMaxLength(500);
        
        builder.Property(x => x.Type)
            .IsRequired();
        
        builder.Property(x => x.Icon)
            .HasMaxLength(50);
        
        builder.Property(x => x.Color)
            .HasMaxLength(10);
        
        builder.HasOne(x => x.ParentCategory)
            .WithMany(x => x.SubCategories)
            .HasForeignKey(x => x.ParentCategoryId)
            .OnDelete(DeleteBehavior.Restrict);
        
        // Indexes
        builder.HasIndex(x => x.Name);
        builder.HasIndex(x => x.Type);
        builder.HasIndex(x => x.ParentCategoryId);
    }
}

public class BankAccountConfiguration : IEntityTypeConfiguration<BankAccount>
{
    public void Configure(EntityTypeBuilder<BankAccount> builder)
    {
        builder.ToTable("BankAccounts");
        
        builder.HasKey(x => x.Id);
        
        builder.Property(x => x.AccountName)
            .IsRequired()
            .HasMaxLength(200);
        
        builder.Property(x => x.AccountNumber)
            .IsRequired()
            .HasMaxLength(50);
        
        builder.Property(x => x.BankCode)
            .IsRequired()
            .HasMaxLength(10);
        
        builder.Property(x => x.BankName)
            .IsRequired()
            .HasMaxLength(200);
        
        builder.Property(x => x.BankShortName)
            .HasMaxLength(50);
        
        builder.Property(x => x.BranchName)
            .HasMaxLength(200);
        
        builder.Property(x => x.BankLogoUrl)
            .HasMaxLength(500);
        
        builder.Property(x => x.Note)
            .HasMaxLength(500);
        
        builder.Property(x => x.VietQRTemplate)
            .HasMaxLength(20)
            .HasDefaultValue("compact2");
        
        // Indexes
        builder.HasIndex(x => x.AccountNumber);
        builder.HasIndex(x => x.BankCode);
        builder.HasIndex(x => x.IsDefault);
    }
}

using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class PaymentTransactionConfiguration : IEntityTypeConfiguration<PaymentTransaction>
{
    public void Configure(EntityTypeBuilder<PaymentTransaction> builder)
    {
        builder.HasKey(pt => pt.Id);

        builder.Property(pt => pt.Type)
            .IsRequired()
            .HasMaxLength(100);

        builder.Property(pt => pt.Amount)
            .HasPrecision(18, 2)
            .IsRequired();

        builder.Property(pt => pt.PaymentMethod)
            .HasMaxLength(100);

        builder.Property(pt => pt.Description)
            .HasMaxLength(500);

        builder.Property(pt => pt.Note)
            .HasMaxLength(500);

        builder.Property(pt => pt.Status)
            .IsRequired()
            .HasMaxLength(50);

        // Relationship with Payslip (optional)
        builder.HasOne(pt => pt.Payslip)
            .WithMany()
            .HasForeignKey(pt => pt.PayslipId)
            .OnDelete(DeleteBehavior.SetNull);

        // Relationship with AdvanceRequest (optional)
        builder.HasOne(pt => pt.AdvanceRequest)
            .WithMany()
            .HasForeignKey(pt => pt.AdvanceRequestId)
            .OnDelete(DeleteBehavior.SetNull);

        // Relationship with Employee (optional)
        builder.HasOne(pt => pt.Employee)
            .WithMany()
            .HasForeignKey(pt => pt.EmployeeId)
            .OnDelete(DeleteBehavior.SetNull);

        // Relationship with EmployeeUser (optional)
        builder.HasOne(pt => pt.EmployeeUser)
            .WithMany()
            .HasForeignKey(pt => pt.EmployeeUserId)
            .OnDelete(DeleteBehavior.SetNull);

        // Indexes
        builder.HasIndex(pt => pt.EmployeeUserId)
            .HasDatabaseName("IX_PaymentTransactions_EmployeeUserId");

        builder.HasIndex(pt => pt.TransactionDate)
            .HasDatabaseName("IX_PaymentTransactions_Date");

        builder.HasIndex(pt => new { pt.EmployeeUserId, pt.ForMonth, pt.ForYear })
            .HasDatabaseName("IX_PaymentTransactions_Employee_Period");
    }
}

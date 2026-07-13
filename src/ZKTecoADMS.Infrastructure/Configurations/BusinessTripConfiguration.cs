using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class BusinessTripCaseConfiguration : IEntityTypeConfiguration<BusinessTripCase>
{
    public void Configure(EntityTypeBuilder<BusinessTripCase> builder)
    {
        builder.HasKey(x => x.Id);
        builder.Property(x => x.CaseCode).HasMaxLength(30).IsRequired();
        builder.Property(x => x.Title).HasMaxLength(300).IsRequired();
        builder.Property(x => x.Destination).HasMaxLength(300);
        builder.Property(x => x.Note).HasMaxLength(1000);
        builder.Property(x => x.Status).HasConversion<int>();
        builder.Property(x => x.AdvanceAmount).HasPrecision(18, 2);
        builder.Property(x => x.SettledAmount).HasPrecision(18, 2);
        builder.Property(x => x.BalanceAmount).HasPrecision(18, 2);

        builder.HasIndex(x => x.StoreId).HasDatabaseName("IX_BusinessTripCases_StoreId");
        builder.HasIndex(x => x.EmployeeId).HasDatabaseName("IX_BusinessTripCases_EmployeeId");
        builder.HasIndex(x => x.Status).HasDatabaseName("IX_BusinessTripCases_Status");
        builder.HasIndex(x => x.CaseCode).HasDatabaseName("IX_BusinessTripCases_CaseCode");
    }
}

public class BusinessTripAdvanceClaimConfiguration : IEntityTypeConfiguration<BusinessTripAdvanceClaim>
{
    public void Configure(EntityTypeBuilder<BusinessTripAdvanceClaim> builder)
    {
        builder.HasKey(x => x.Id);
        builder.Property(x => x.Amount).HasPrecision(18, 2);
        builder.Property(x => x.Reason).HasMaxLength(1000).IsRequired();
        builder.Property(x => x.Status).HasConversion<int>();

        builder.HasOne(x => x.Case)
            .WithOne(c => c.AdvanceClaim)
            .HasForeignKey<BusinessTripAdvanceClaim>(x => x.CaseId)
            .OnDelete(DeleteBehavior.Cascade);
    }
}

public class BusinessTripSettlementClaimConfiguration : IEntityTypeConfiguration<BusinessTripSettlementClaim>
{
    public void Configure(EntityTypeBuilder<BusinessTripSettlementClaim> builder)
    {
        builder.HasKey(x => x.Id);
        builder.Property(x => x.AdvanceAmount).HasPrecision(18, 2);
        builder.Property(x => x.TotalAmount).HasPrecision(18, 2);
        builder.Property(x => x.TotalWithInvoice).HasPrecision(18, 2);
        builder.Property(x => x.TotalWithoutInvoice).HasPrecision(18, 2);
        builder.Property(x => x.BalanceAmount).HasPrecision(18, 2);
        builder.Property(x => x.Status).HasConversion<int>();
        builder.Property(x => x.SettlementType).HasConversion<int>();

        builder.HasOne(x => x.Case)
            .WithOne(c => c.SettlementClaim)
            .HasForeignKey<BusinessTripSettlementClaim>(x => x.CaseId)
            .OnDelete(DeleteBehavior.Cascade);
    }
}

public class BusinessTripExpenseLineConfiguration : IEntityTypeConfiguration<BusinessTripExpenseLine>
{
    public void Configure(EntityTypeBuilder<BusinessTripExpenseLine> builder)
    {
        builder.HasKey(x => x.Id);
        builder.Property(x => x.Amount).HasPrecision(18, 2);
    }
}

public class BusinessTripExpenseCategoryConfiguration : IEntityTypeConfiguration<BusinessTripExpenseCategory>
{
    public void Configure(EntityTypeBuilder<BusinessTripExpenseCategory> builder)
    {
        builder.HasKey(x => x.Id);
        builder.Property(x => x.Code).HasMaxLength(50).IsRequired();
        builder.Property(x => x.Name).HasMaxLength(200).IsRequired();
        builder.Property(x => x.MaxAmountPerLine).HasPrecision(18, 2);
        builder.Property(x => x.MaxAmountPerMonth).HasPrecision(18, 2);
        builder.HasIndex(x => new { x.StoreId, x.Code }).HasDatabaseName("IX_BusinessTripExpenseCategories_Store_Code");
    }
}

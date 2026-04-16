using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class EmployeeTaxDeductionConfiguration : IEntityTypeConfiguration<EmployeeTaxDeduction>
{
    public void Configure(EntityTypeBuilder<EmployeeTaxDeduction> builder)
    {
        builder.ToTable("EmployeeTaxDeductions");
        builder.HasKey(e => e.Id);

        builder.Property(e => e.MandatoryInsurance).HasPrecision(18, 2);
        builder.Property(e => e.OtherExemptions).HasPrecision(18, 2);

        builder.HasIndex(e => new { e.EmployeeId, e.StoreId })
            .IsUnique()
            .HasDatabaseName("IX_EmployeeTaxDeductions_EmployeeId_StoreId");
    }
}

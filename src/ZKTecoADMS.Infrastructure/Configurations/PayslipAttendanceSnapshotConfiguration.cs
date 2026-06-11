using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class PayslipAttendanceSnapshotConfiguration : IEntityTypeConfiguration<PayslipAttendanceSnapshot>
{
    public void Configure(EntityTypeBuilder<PayslipAttendanceSnapshot> builder)
    {
        builder.HasKey(x => x.Id);

        builder.Property(x => x.SnapshotJson)
            .HasColumnType("text")
            .IsRequired();

        builder.HasIndex(x => x.PayslipId)
            .IsUnique();

        builder.HasOne(x => x.Payslip)
            .WithMany()
            .HasForeignKey(x => x.PayslipId)
            .OnDelete(DeleteBehavior.Cascade);

        builder.HasOne(x => x.Store)
            .WithMany()
            .HasForeignKey(x => x.StoreId)
            .OnDelete(DeleteBehavior.Restrict)
            .IsRequired(false);
    }
}

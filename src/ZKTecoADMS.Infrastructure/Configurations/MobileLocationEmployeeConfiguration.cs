using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class MobileLocationEmployeeConfiguration : IEntityTypeConfiguration<MobileLocationEmployee>
{
    public void Configure(EntityTypeBuilder<MobileLocationEmployee> builder)
    {
        builder.HasIndex(x => new { x.StoreId, x.WorkLocationId, x.EmployeeId })
            .IsUnique()
            .HasFilter("\"Deleted\" IS NULL");

        builder.HasOne(x => x.WorkLocation)
            .WithMany()
            .HasForeignKey(x => x.WorkLocationId)
            .OnDelete(DeleteBehavior.Cascade);

        builder.Property(x => x.EmployeeId).HasMaxLength(100);
        builder.Property(x => x.EmployeeName).HasMaxLength(200);
    }
}

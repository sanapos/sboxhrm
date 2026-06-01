using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class MealRecordConfiguration : IEntityTypeConfiguration<MealRecord>
{
    public void Configure(EntityTypeBuilder<MealRecord> builder)
    {
        builder.HasOne(m => m.Attendance)
            .WithMany()
            .HasForeignKey(m => m.AttendanceId)
            .OnDelete(DeleteBehavior.SetNull);
    }
}

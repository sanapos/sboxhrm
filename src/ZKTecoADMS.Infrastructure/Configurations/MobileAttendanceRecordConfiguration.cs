using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class MobileAttendanceRecordConfiguration : IEntityTypeConfiguration<MobileAttendanceRecord>
{
    public void Configure(EntityTypeBuilder<MobileAttendanceRecord> builder)
    {
        builder.Property(x => x.SitePhotoUrl).HasMaxLength(500);
        builder.Property(x => x.FaceImageUrl).HasMaxLength(500);
    }
}

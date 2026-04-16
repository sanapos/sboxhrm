using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class GeofenceConfiguration : IEntityTypeConfiguration<Geofence>
{
    public void Configure(EntityTypeBuilder<Geofence> builder)
    {
        builder.ToTable("Geofences");

        builder.HasKey(g => g.Id);

        builder.Property(g => g.Name)
            .IsRequired()
            .HasMaxLength(200);

        builder.Property(g => g.Description)
            .HasMaxLength(500);

        builder.Property(g => g.Address)
            .HasMaxLength(500);

        builder.Property(g => g.Latitude)
            .IsRequired();

        builder.Property(g => g.Longitude)
            .IsRequired();

        builder.Property(g => g.RadiusMeters)
            .IsRequired()
            .HasDefaultValue(100);

        builder.Property(g => g.IsActive)
            .HasDefaultValue(true);

        builder.Property(g => g.IsPrimary)
            .HasDefaultValue(false);

        builder.Property(g => g.CheckInToleranceMinutes)
            .HasDefaultValue(15);

        builder.Property(g => g.CheckOutToleranceMinutes)
            .HasDefaultValue(15);

        builder.Property(g => g.AllowOutsideCheckIn)
            .HasDefaultValue(false);

        // Indexes
        builder.HasIndex(g => g.StoreId);
        builder.HasIndex(g => new { g.StoreId, g.IsActive });
        builder.HasIndex(g => new { g.Latitude, g.Longitude });

        // Relationships
        builder.HasOne(g => g.Store)
            .WithMany()
            .HasForeignKey(g => g.StoreId)
            .OnDelete(DeleteBehavior.Cascade);

        // Soft delete + tenant filters are applied centrally in ZKTecoDbContext.OnModelCreating
    }
}

using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class SystemAnnouncementConfiguration : IEntityTypeConfiguration<SystemAnnouncement>
{
    public void Configure(EntityTypeBuilder<SystemAnnouncement> builder)
    {
        builder.ToTable("SystemAnnouncements");
        builder.HasKey(x => x.Id);

        builder.Property(x => x.Title).IsRequired().HasMaxLength(200);
        builder.Property(x => x.Content).IsRequired();
        builder.Property(x => x.AudienceJson).HasColumnType("jsonb").HasDefaultValue("{}");

        builder.Property(x => x.Kind).HasConversion<int>();
        builder.Property(x => x.Severity).HasConversion<int>();
        builder.Property(x => x.Status).HasConversion<int>();
        builder.Property(x => x.Channels).HasConversion<int>();

        builder.HasIndex(x => x.Status).HasDatabaseName("IX_SystemAnnouncements_Status");
        builder.HasIndex(x => x.ScheduleAt).HasDatabaseName("IX_SystemAnnouncements_ScheduleAt");
        builder.HasIndex(x => x.ExpiresAt).HasDatabaseName("IX_SystemAnnouncements_ExpiresAt");
        builder.HasIndex(x => new { x.Status, x.ExpiresAt }).HasDatabaseName("IX_SystemAnnouncements_Status_Expires");

        builder.HasMany(x => x.Deliveries)
            .WithOne(d => d.Announcement)
            .HasForeignKey(d => d.AnnouncementId)
            .OnDelete(DeleteBehavior.Cascade);
    }
}

public class AnnouncementDeliveryConfiguration : IEntityTypeConfiguration<AnnouncementDelivery>
{
    public void Configure(EntityTypeBuilder<AnnouncementDelivery> builder)
    {
        builder.ToTable("AnnouncementDeliveries");
        builder.HasKey(x => x.Id);

        builder.Property(x => x.Channel).HasConversion<int>();
        builder.Property(x => x.Status).HasConversion<int>();
        builder.Property(x => x.ErrorMessage).HasMaxLength(500);

        builder.HasOne(x => x.User)
            .WithMany()
            .HasForeignKey(x => x.UserId)
            .OnDelete(DeleteBehavior.Cascade);

        builder.HasOne(x => x.Store)
            .WithMany()
            .HasForeignKey(x => x.StoreId)
            .OnDelete(DeleteBehavior.SetNull);

        builder.HasIndex(x => x.AnnouncementId).HasDatabaseName("IX_AnnouncementDeliveries_AnnId");
        builder.HasIndex(x => x.UserId).HasDatabaseName("IX_AnnouncementDeliveries_UserId");
        builder.HasIndex(x => x.StoreId).HasDatabaseName("IX_AnnouncementDeliveries_StoreId");
        builder.HasIndex(x => new { x.AnnouncementId, x.UserId, x.Channel })
            .IsUnique()
            .HasDatabaseName("UX_AnnouncementDeliveries_Ann_User_Channel");
        builder.HasIndex(x => new { x.UserId, x.Status }).HasDatabaseName("IX_AnnouncementDeliveries_User_Status");
    }
}

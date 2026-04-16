using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class NotificationConfiguration : IEntityTypeConfiguration<Notification>
{
    public void Configure(EntityTypeBuilder<Notification> builder)
    {
        builder.HasKey(n => n.Id);

        builder.Property(n => n.Title)
            .HasMaxLength(200);

        builder.Property(n => n.Message)
            .IsRequired()
            .HasMaxLength(2000);

        builder.Property(n => n.Type)
            .HasConversion<int>();

        builder.Property(n => n.RelatedUrl)
            .HasMaxLength(500);

        builder.Property(n => n.RelatedEntityType)
            .HasMaxLength(100);

        builder.Property(n => n.CategoryCode)
            .HasMaxLength(50);

        // Indexes
        builder.HasIndex(n => n.TargetUserId)
            .HasDatabaseName("IX_Notifications_TargetUserId");

        builder.HasIndex(n => n.IsRead)
            .HasDatabaseName("IX_Notifications_IsRead");

        builder.HasIndex(n => n.Type)
            .HasDatabaseName("IX_Notifications_Type");

        builder.HasIndex(n => new { n.TargetUserId, n.IsRead })
            .HasDatabaseName("IX_Notifications_User_Read");

        builder.HasIndex(n => n.CategoryCode)
            .HasDatabaseName("IX_Notifications_CategoryCode");

        // StoreId composite indexes for multi-tenant query performance
        builder.HasIndex(n => n.StoreId)
            .HasDatabaseName("IX_Notifications_StoreId");

        builder.HasIndex(n => new { n.StoreId, n.TargetUserId, n.IsRead })
            .HasDatabaseName("IX_Notifications_Store_User_Read");

        builder.HasIndex(n => new { n.StoreId, n.Timestamp })
            .HasDatabaseName("IX_Notifications_Store_Timestamp");
    }
}

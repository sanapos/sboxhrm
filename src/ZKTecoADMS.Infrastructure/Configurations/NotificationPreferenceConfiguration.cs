using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class NotificationPreferenceConfiguration : IEntityTypeConfiguration<NotificationPreference>
{
    public void Configure(EntityTypeBuilder<NotificationPreference> builder)
    {
        builder.HasKey(e => e.Id);

        builder.Property(e => e.CategoryCode)
            .IsRequired()
            .HasMaxLength(50);

        builder.HasIndex(e => new { e.UserId, e.CategoryCode, e.StoreId })
            .IsUnique()
            .HasDatabaseName("IX_NotificationPreferences_User_Category_Store");

        builder.HasIndex(e => e.UserId)
            .HasDatabaseName("IX_NotificationPreferences_UserId");
    }
}

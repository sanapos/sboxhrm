using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class UserDeviceTokenConfiguration : IEntityTypeConfiguration<UserDeviceToken>
{
    public void Configure(EntityTypeBuilder<UserDeviceToken> builder)
    {
        builder.ToTable("UserDeviceTokens");
        builder.HasKey(e => e.Id);

        builder.Property(e => e.Token)
            .IsRequired()
            .HasMaxLength(512);

        builder.Property(e => e.Platform)
            .IsRequired()
            .HasMaxLength(16);

        builder.Property(e => e.DeviceName).HasMaxLength(128);
        builder.Property(e => e.AppVersion).HasMaxLength(32);

        // A given FCM token is globally unique - re-registering the same token
        // (e.g. after re-login on the same device) updates the existing row.
        builder.HasIndex(e => e.Token)
            .IsUnique()
            .HasDatabaseName("UX_UserDeviceTokens_Token");

        builder.HasIndex(e => e.UserId)
            .HasDatabaseName("IX_UserDeviceTokens_UserId");

        builder.HasIndex(e => new { e.UserId, e.IsDisabled })
            .HasDatabaseName("IX_UserDeviceTokens_User_Disabled");
    }
}

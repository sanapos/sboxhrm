using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class PosShippingCarrierSettingConfiguration : IEntityTypeConfiguration<PosShippingCarrierSetting>
{
    public void Configure(EntityTypeBuilder<PosShippingCarrierSetting> builder)
    {
        builder.ToTable("PosShippingCarrierSettings");
        builder.HasKey(x => x.Id);
        builder.HasIndex(x => new { x.StoreId, x.CarrierCode }).IsUnique();
        builder.Property(x => x.CarrierCode).HasMaxLength(30).IsRequired();
        builder.Property(x => x.ApiToken).HasMaxLength(2000);
        builder.Property(x => x.ShopId).HasMaxLength(100);
        builder.Property(x => x.Username).HasMaxLength(100);
        builder.Property(x => x.Password).HasMaxLength(200);
        builder.Property(x => x.ApiBaseUrl).HasMaxLength(300);
        builder.Property(x => x.PickupName).HasMaxLength(120);
        builder.Property(x => x.PickupPhone).HasMaxLength(30);
        builder.Property(x => x.PickupAddress).HasMaxLength(500);
        builder.Property(x => x.FromProvinceName).HasMaxLength(100);
        builder.Property(x => x.FromDistrictName).HasMaxLength(100);
        builder.Property(x => x.FromWardName).HasMaxLength(100);
        builder.Property(x => x.FromDistrictId).HasMaxLength(40);
        builder.Property(x => x.FromWardCode).HasMaxLength(40);
        builder.Property(x => x.FromProvinceId).HasMaxLength(40);
        builder.Property(x => x.ExtraJson).HasMaxLength(4000);
        builder.HasOne(x => x.Store).WithMany().HasForeignKey(x => x.StoreId)
            .OnDelete(DeleteBehavior.Cascade);
    }
}

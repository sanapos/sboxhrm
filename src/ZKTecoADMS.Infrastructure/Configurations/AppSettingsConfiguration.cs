using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class AppSettingsConfiguration : IEntityTypeConfiguration<AppSettings>
{
    public void Configure(EntityTypeBuilder<AppSettings> builder)
    {
        builder.ToTable("AppSettings");
        
        builder.HasKey(x => x.Id);
        
        builder.Property(x => x.Key)
            .IsRequired()
            .HasMaxLength(100);
            
        builder.HasIndex(x => new { x.StoreId, x.Key })
            .IsUnique();

        builder.HasOne(x => x.Store)
            .WithMany()
            .HasForeignKey(x => x.StoreId)
            .OnDelete(DeleteBehavior.Cascade);
            
        builder.Property(x => x.Value)
            .HasColumnType("text");
            
        builder.Property(x => x.Description)
            .HasMaxLength(500);
            
        builder.Property(x => x.Group)
            .HasMaxLength(50);
            
        builder.Property(x => x.DataType)
            .HasMaxLength(50);
    }
}

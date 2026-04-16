using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class StoreConfiguration : IEntityTypeConfiguration<Store>
{
    public void Configure(EntityTypeBuilder<Store> builder)
    {
        builder.HasKey(e => e.Id);
        
        builder.Property(e => e.Name)
            .IsRequired()
            .HasMaxLength(100);
        
        builder.Property(e => e.Code)
            .IsRequired()
            .HasMaxLength(50);
        
        // Index unique cho Code
        builder.HasIndex(e => e.Code)
            .IsUnique();
            
        builder.Property(e => e.Description)
            .HasMaxLength(500);
            
        builder.Property(e => e.Address)
            .HasMaxLength(255);
            
        builder.Property(e => e.Phone)
            .HasMaxLength(20);

        // Owner relationship (1-1)
        builder.HasOne(s => s.Owner)
            .WithOne(u => u.OwnedStore)
            .HasForeignKey<Store>(s => s.OwnerId)
            .OnDelete(DeleteBehavior.Restrict);

        // Users in store (1-Many)
        builder.HasMany(s => s.Users)
            .WithOne(u => u.Store)
            .HasForeignKey(u => u.StoreId)
            .OnDelete(DeleteBehavior.SetNull);

        // Devices in store (1-Many)
        builder.HasMany(s => s.Devices)
            .WithOne()
            .HasForeignKey("StoreId")
            .OnDelete(DeleteBehavior.SetNull);
    }
}

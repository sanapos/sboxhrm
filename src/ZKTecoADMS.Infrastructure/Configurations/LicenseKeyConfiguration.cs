using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class LicenseKeyConfiguration : IEntityTypeConfiguration<LicenseKey>
{
    public void Configure(EntityTypeBuilder<LicenseKey> builder)
    {
        builder.HasKey(e => e.Id);
        
        builder.Property(e => e.Key)
            .IsRequired()
            .HasMaxLength(50);
        
        // Index unique cho Key
        builder.HasIndex(e => e.Key)
            .IsUnique();
            
        builder.Property(e => e.Notes)
            .HasMaxLength(500);

        // Relationship with Store
        builder.HasOne(l => l.Store)
            .WithMany(s => s.LicenseKeys)
            .HasForeignKey(l => l.StoreId)
            .OnDelete(DeleteBehavior.SetNull);
            
        // Relationship with Agent
        builder.HasOne(l => l.Agent)
            .WithMany(a => a.LicenseKeys)
            .HasForeignKey(l => l.AgentId)
            .OnDelete(DeleteBehavior.SetNull);
    }
}

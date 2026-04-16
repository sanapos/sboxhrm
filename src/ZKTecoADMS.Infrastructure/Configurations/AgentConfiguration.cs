using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class AgentConfiguration : IEntityTypeConfiguration<Agent>
{
    public void Configure(EntityTypeBuilder<Agent> builder)
    {
        builder.ToTable("Agents");
        
        builder.HasKey(x => x.Id);
        
        builder.Property(x => x.Name)
            .IsRequired()
            .HasMaxLength(200);
            
        builder.Property(x => x.Code)
            .IsRequired()
            .HasMaxLength(50);
            
        builder.HasIndex(x => x.Code)
            .IsUnique();
            
        builder.Property(x => x.Description)
            .HasMaxLength(500);
            
        builder.Property(x => x.Address)
            .HasMaxLength(500);
            
        builder.Property(x => x.Phone)
            .HasMaxLength(20);
            
        builder.Property(x => x.Email)
            .HasMaxLength(100);
            
        builder.Property(x => x.LicenseKey)
            .HasMaxLength(100);
        
        // Relationship with User
        builder.HasOne(x => x.User)
            .WithOne()
            .HasForeignKey<Agent>(x => x.UserId)
            .OnDelete(DeleteBehavior.SetNull);
            
        // Relationship with Stores
        builder.HasMany(x => x.Stores)
            .WithOne(s => s.Agent)
            .HasForeignKey(s => s.AgentId)
            .OnDelete(DeleteBehavior.SetNull);
    }
}

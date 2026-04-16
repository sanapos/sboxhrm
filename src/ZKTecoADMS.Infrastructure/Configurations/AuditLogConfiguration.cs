using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class AuditLogConfiguration : IEntityTypeConfiguration<AuditLog>
{
    public void Configure(EntityTypeBuilder<AuditLog> builder)
    {
        builder.ToTable("AuditLogs");
        
        builder.HasKey(x => x.Id);
        
        builder.Property(x => x.Action)
            .IsRequired()
            .HasMaxLength(100);
            
        builder.Property(x => x.EntityType)
            .IsRequired()
            .HasMaxLength(100);
            
        builder.Property(x => x.EntityId)
            .HasMaxLength(100);
            
        builder.Property(x => x.EntityName)
            .HasMaxLength(500);
            
        builder.Property(x => x.Details)
            .HasColumnType("text");
            
        builder.Property(x => x.UserEmail)
            .HasMaxLength(256);
            
        builder.Property(x => x.UserName)
            .HasMaxLength(256);
            
        builder.Property(x => x.UserRole)
            .HasMaxLength(50);
            
        builder.Property(x => x.StoreName)
            .HasMaxLength(256);
            
        builder.Property(x => x.IpAddress)
            .HasMaxLength(50);
            
        builder.Property(x => x.UserAgent)
            .HasMaxLength(1000);
            
        builder.Property(x => x.Status)
            .HasMaxLength(50);
            
        builder.Property(x => x.ErrorMessage)
            .HasMaxLength(2000);
            
        // Indexes for better query performance
        builder.HasIndex(x => x.Timestamp);
        builder.HasIndex(x => x.Action);
        builder.HasIndex(x => x.EntityType);
        builder.HasIndex(x => x.UserId);
        builder.HasIndex(x => x.StoreId);
        builder.HasIndex(x => new { x.Timestamp, x.Action });
    }
}

using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class FaceTemplateConfiguration : IEntityTypeConfiguration<FaceTemplate>
{
    public void Configure(EntityTypeBuilder<FaceTemplate> builder)
    {
        builder.HasKey(e => e.Id);
        builder.HasIndex(e => new { e.EmployeeId, e.FaceIndex }).IsUnique();

        builder.HasOne(e => e.Employee)
            .WithMany(u => u.FaceTemplates)
            .HasForeignKey(e => e.EmployeeId)
            .OnDelete(DeleteBehavior.Cascade);
    }
}
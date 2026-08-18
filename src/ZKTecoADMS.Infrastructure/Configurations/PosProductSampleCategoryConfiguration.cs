using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class PosProductSampleCategoryConfiguration : IEntityTypeConfiguration<PosProductSampleCategory>
{
    public void Configure(EntityTypeBuilder<PosProductSampleCategory> builder)
    {
        builder.ToTable("PosProductSampleCategory");
        builder.HasKey(x => x.Id);
        builder.Property(x => x.Name).IsRequired().HasMaxLength(200);
        builder.HasIndex(x => x.Name);
        builder.HasIndex(x => new { x.Kind, x.SortOrder });
        builder.HasOne(x => x.Parent)
            .WithMany(x => x.Children)
            .HasForeignKey(x => x.ParentId)
            .OnDelete(DeleteBehavior.SetNull);
    }
}

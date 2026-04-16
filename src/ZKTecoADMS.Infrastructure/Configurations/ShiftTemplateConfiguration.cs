using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class ShiftTemplateConfiguration : IEntityTypeConfiguration<ShiftTemplate>
{
    public void Configure(EntityTypeBuilder<ShiftTemplate> builder)
    {
        builder.HasKey(e => e.Id);

        builder.HasOne(s => s.Manager)
            .WithMany()
            .HasForeignKey(s => s.ManagerId)
            .OnDelete(DeleteBehavior.Restrict);

        builder.HasOne(s => s.Store)
            .WithMany()
            .HasForeignKey(s => s.StoreId)
            .OnDelete(DeleteBehavior.SetNull);
    }
}

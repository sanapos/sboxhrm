using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class FeedbackConfiguration : IEntityTypeConfiguration<Feedback>
{
    public void Configure(EntityTypeBuilder<Feedback> builder)
    {
        builder.HasKey(f => f.Id);

        builder.HasOne(f => f.SenderEmployee)
            .WithMany()
            .HasForeignKey(f => f.SenderEmployeeId)
            .OnDelete(DeleteBehavior.SetNull);

        builder.HasOne(f => f.RecipientEmployee)
            .WithMany()
            .HasForeignKey(f => f.RecipientEmployeeId)
            .OnDelete(DeleteBehavior.SetNull);

        builder.HasOne(f => f.RespondedByEmployee)
            .WithMany()
            .HasForeignKey(f => f.RespondedByEmployeeId)
            .OnDelete(DeleteBehavior.SetNull);

        builder.HasIndex(f => new { f.StoreId, f.Status });
        builder.HasIndex(f => f.SenderEmployeeId);
        builder.HasIndex(f => f.RecipientEmployeeId);
    }
}

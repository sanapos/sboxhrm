using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class FeedbackReplyConfiguration : IEntityTypeConfiguration<FeedbackReply>
{
    public void Configure(EntityTypeBuilder<FeedbackReply> builder)
    {
        builder.HasKey(r => r.Id);

        builder.HasOne(r => r.Feedback)
            .WithMany(f => f.Replies)
            .HasForeignKey(r => r.FeedbackId)
            .OnDelete(DeleteBehavior.Cascade);

        builder.HasOne(r => r.SenderEmployee)
            .WithMany()
            .HasForeignKey(r => r.SenderEmployeeId)
            .OnDelete(DeleteBehavior.SetNull);

        builder.HasIndex(r => r.FeedbackId);
        builder.HasIndex(r => r.SenderEmployeeId);
    }
}

using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class NotificationTemplateConfiguration : IEntityTypeConfiguration<NotificationTemplate>
{
    public void Configure(EntityTypeBuilder<NotificationTemplate> b)
    {
        b.ToTable("NotificationTemplates");
        b.HasKey(x => x.Id);
        b.Property(x => x.Code).IsRequired().HasMaxLength(100);
        b.Property(x => x.Title).IsRequired().HasMaxLength(200);
        b.Property(x => x.Body).IsRequired();
        b.Property(x => x.VariablesJson).HasColumnType("jsonb");
        b.Property(x => x.Channels).HasConversion<int>();
        b.HasIndex(x => x.Code).IsUnique().HasDatabaseName("UX_NotificationTemplates_Code");
    }
}

public class MarketingCampaignConfiguration : IEntityTypeConfiguration<MarketingCampaign>
{
    public void Configure(EntityTypeBuilder<MarketingCampaign> b)
    {
        b.ToTable("MarketingCampaigns");
        b.HasKey(x => x.Id);
        b.Property(x => x.Name).IsRequired().HasMaxLength(200);
        b.Property(x => x.AudienceJson).HasColumnType("jsonb").HasDefaultValue("{}");
        b.Property(x => x.Channels).HasConversion<int>();
        b.Property(x => x.Status).HasConversion<int>();
        b.HasOne(x => x.Template)
            .WithMany()
            .HasForeignKey(x => x.TemplateId)
            .OnDelete(DeleteBehavior.SetNull);
        b.HasIndex(x => x.Status).HasDatabaseName("IX_MarketingCampaigns_Status");
        b.HasIndex(x => x.ScheduleAt).HasDatabaseName("IX_MarketingCampaigns_ScheduleAt");
    }
}

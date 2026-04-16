using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class PenaltySettingConfiguration : IEntityTypeConfiguration<PenaltySetting>
{
    public void Configure(EntityTypeBuilder<PenaltySetting> builder)
    {
        builder.HasKey(ps => ps.Id);

        // Late penalties
        builder.Property(ps => ps.LatePenalty1).HasPrecision(18, 2);
        builder.Property(ps => ps.LatePenalty2).HasPrecision(18, 2);
        builder.Property(ps => ps.LatePenalty3).HasPrecision(18, 2);

        // Early leave penalties
        builder.Property(ps => ps.EarlyPenalty1).HasPrecision(18, 2);
        builder.Property(ps => ps.EarlyPenalty2).HasPrecision(18, 2);
        builder.Property(ps => ps.EarlyPenalty3).HasPrecision(18, 2);

        // Repeat penalties
        builder.Property(ps => ps.RepeatPenalty1).HasPrecision(18, 2);
        builder.Property(ps => ps.RepeatPenalty2).HasPrecision(18, 2);
        builder.Property(ps => ps.RepeatPenalty3).HasPrecision(18, 2);

        // Other penalties
        builder.Property(ps => ps.ForgotCheckPenalty).HasPrecision(18, 2);
        builder.Property(ps => ps.UnauthorizedLeavePenalty).HasPrecision(18, 2);
        builder.Property(ps => ps.ViolationPenalty).HasPrecision(18, 2);
    }
}

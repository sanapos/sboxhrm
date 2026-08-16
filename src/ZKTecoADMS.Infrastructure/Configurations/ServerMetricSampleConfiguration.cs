using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class ServerMetricSampleConfiguration : IEntityTypeConfiguration<ServerMetricSample>
{
    public void Configure(EntityTypeBuilder<ServerMetricSample> builder)
    {
        builder.ToTable("ServerMetricSamples");
        builder.HasKey(x => x.Id);
        builder.Property(x => x.Source).IsRequired().HasMaxLength(20);
        builder.HasIndex(x => x.SampledAt);
    }
}

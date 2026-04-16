using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class FieldLocationAssignmentConfiguration : IEntityTypeConfiguration<FieldLocationAssignment>
{
    public void Configure(EntityTypeBuilder<FieldLocationAssignment> builder)
    {
        builder.ToTable("FieldLocationAssignments");
        builder.HasKey(f => f.Id);

        builder.Property(f => f.EmployeeId).IsRequired().HasMaxLength(100);
        builder.Property(f => f.EmployeeName).HasMaxLength(200);
        builder.Property(f => f.Note).HasMaxLength(500);

        builder.HasIndex(f => new { f.StoreId, f.EmployeeId, f.LocationId, f.DayOfWeek })
            .HasDatabaseName("IX_FieldLocationAssign_Employee_Location");
    }
}

public class VisitReportConfiguration : IEntityTypeConfiguration<VisitReport>
{
    public void Configure(EntityTypeBuilder<VisitReport> builder)
    {
        builder.ToTable("VisitReports");
        builder.HasKey(v => v.Id);

        builder.Property(v => v.EmployeeId).IsRequired().HasMaxLength(100);
        builder.Property(v => v.EmployeeName).HasMaxLength(200);
        builder.Property(v => v.LocationName).HasMaxLength(200);
        builder.Property(v => v.Status).IsRequired().HasMaxLength(50);
        builder.Property(v => v.ReportNote).HasMaxLength(2000);
        builder.Property(v => v.ReviewedBy).HasMaxLength(200);
        builder.Property(v => v.ReviewNote).HasMaxLength(500);
        builder.Property(v => v.OutsideRadius).HasDefaultValue(false);

        builder.HasIndex(v => new { v.StoreId, v.EmployeeId, v.VisitDate })
            .HasDatabaseName("IX_VisitReport_Employee_Date");
        builder.HasIndex(v => new { v.StoreId, v.LocationId, v.VisitDate })
            .HasDatabaseName("IX_VisitReport_Location_Date");
        builder.HasIndex(v => new { v.StoreId, v.Status })
            .HasDatabaseName("IX_VisitReport_Status");
        builder.HasIndex(v => new { v.StoreId, v.JourneyId })
            .HasDatabaseName("IX_VisitReport_Journey");
    }
}

public class JourneyTrackingConfiguration : IEntityTypeConfiguration<JourneyTracking>
{
    public void Configure(EntityTypeBuilder<JourneyTracking> builder)
    {
        builder.ToTable("JourneyTrackings");
        builder.HasKey(j => j.Id);

        builder.Property(j => j.EmployeeId).IsRequired().HasMaxLength(100);
        builder.Property(j => j.EmployeeName).HasMaxLength(200);
        builder.Property(j => j.Status).IsRequired().HasMaxLength(30);
        builder.Property(j => j.Note).HasMaxLength(1000);
        builder.Property(j => j.ReviewedBy).HasMaxLength(200);
        builder.Property(j => j.ReviewNote).HasMaxLength(500);

        builder.HasIndex(j => new { j.StoreId, j.EmployeeId, j.JourneyDate })
            .HasDatabaseName("IX_Journey_Employee_Date");
        builder.HasIndex(j => new { j.StoreId, j.Status })
            .HasDatabaseName("IX_Journey_Status");
    }
}

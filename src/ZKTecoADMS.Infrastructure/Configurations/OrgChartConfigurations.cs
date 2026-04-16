using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class OrgPositionConfiguration : IEntityTypeConfiguration<OrgPosition>
{
    public void Configure(EntityTypeBuilder<OrgPosition> builder)
    {
        builder.HasKey(e => e.Id);

        builder.Property(e => e.Code).IsRequired().HasMaxLength(20);
        builder.Property(e => e.Name).IsRequired().HasMaxLength(200);
        builder.Property(e => e.Description).HasMaxLength(500);
        builder.Property(e => e.Color).HasMaxLength(10);
        builder.Property(e => e.IconName).HasMaxLength(50);
        builder.Property(e => e.MaxApprovalAmount).HasColumnType("decimal(18,2)");

        builder.HasIndex(e => new { e.StoreId, e.Code })
            .IsUnique()
            .HasDatabaseName("IX_OrgPositions_StoreId_Code");

        builder.HasIndex(e => e.Level)
            .HasDatabaseName("IX_OrgPositions_Level");

        builder.HasOne(e => e.Store)
            .WithMany()
            .HasForeignKey(e => e.StoreId)
            .OnDelete(DeleteBehavior.SetNull);

        builder.Property(e => e.IsActive).HasDefaultValue(true);
        builder.Property(e => e.CanApprove).HasDefaultValue(false);
    }
}

public class OrgAssignmentConfiguration : IEntityTypeConfiguration<OrgAssignment>
{
    public void Configure(EntityTypeBuilder<OrgAssignment> builder)
    {
        builder.HasKey(e => e.Id);

        // Unique: 1 nhân viên chỉ giữ 1 chức vụ trong 1 phòng ban tại 1 thời điểm
        builder.HasIndex(e => new { e.EmployeeId, e.DepartmentId, e.PositionId })
            .IsUnique()
            .HasDatabaseName("IX_OrgAssignments_Emp_Dept_Pos");

        builder.HasIndex(e => e.EmployeeId)
            .HasDatabaseName("IX_OrgAssignments_EmployeeId");

        builder.HasIndex(e => e.DepartmentId)
            .HasDatabaseName("IX_OrgAssignments_DepartmentId");

        builder.HasIndex(e => e.PositionId)
            .HasDatabaseName("IX_OrgAssignments_PositionId");

        builder.HasOne(e => e.Employee)
            .WithMany()
            .HasForeignKey(e => e.EmployeeId)
            .OnDelete(DeleteBehavior.Cascade);

        builder.HasOne(e => e.Department)
            .WithMany()
            .HasForeignKey(e => e.DepartmentId)
            .OnDelete(DeleteBehavior.Cascade);

        builder.HasOne(e => e.Position)
            .WithMany(p => p.OrgAssignments)
            .HasForeignKey(e => e.PositionId)
            .OnDelete(DeleteBehavior.Restrict);

        builder.HasOne(e => e.ReportToAssignment)
            .WithMany(e => e.DirectReports)
            .HasForeignKey(e => e.ReportToAssignmentId)
            .OnDelete(DeleteBehavior.SetNull);

        builder.HasOne(e => e.Store)
            .WithMany()
            .HasForeignKey(e => e.StoreId)
            .OnDelete(DeleteBehavior.SetNull);

        builder.Property(e => e.IsPrimary).HasDefaultValue(true);
        builder.Property(e => e.IsActive).HasDefaultValue(true);
    }
}

public class ApprovalFlowConfiguration : IEntityTypeConfiguration<ApprovalFlow>
{
    public void Configure(EntityTypeBuilder<ApprovalFlow> builder)
    {
        builder.HasKey(e => e.Id);

        builder.Property(e => e.Code).IsRequired().HasMaxLength(50);
        builder.Property(e => e.Name).IsRequired().HasMaxLength(200);
        builder.Property(e => e.Description).HasMaxLength(500);

        builder.HasIndex(e => new { e.StoreId, e.Code })
            .IsUnique()
            .HasDatabaseName("IX_ApprovalFlows_StoreId_Code");

        builder.HasIndex(e => new { e.StoreId, e.RequestType })
            .HasDatabaseName("IX_ApprovalFlows_StoreId_RequestType");

        builder.HasOne(e => e.Department)
            .WithMany()
            .HasForeignKey(e => e.DepartmentId)
            .OnDelete(DeleteBehavior.SetNull);

        builder.HasOne(e => e.Store)
            .WithMany()
            .HasForeignKey(e => e.StoreId)
            .OnDelete(DeleteBehavior.SetNull);

        builder.Property(e => e.IsActive).HasDefaultValue(true);
    }
}

public class ApprovalStepConfiguration : IEntityTypeConfiguration<ApprovalStep>
{
    public void Configure(EntityTypeBuilder<ApprovalStep> builder)
    {
        builder.HasKey(e => e.Id);

        builder.Property(e => e.Name).IsRequired().HasMaxLength(200);

        builder.HasIndex(e => new { e.ApprovalFlowId, e.StepOrder })
            .IsUnique()
            .HasDatabaseName("IX_ApprovalSteps_FlowId_StepOrder");

        builder.HasOne(e => e.ApprovalFlow)
            .WithMany(f => f.Steps)
            .HasForeignKey(e => e.ApprovalFlowId)
            .OnDelete(DeleteBehavior.Cascade);

        builder.HasOne(e => e.ApproverPosition)
            .WithMany()
            .HasForeignKey(e => e.ApproverPositionId)
            .OnDelete(DeleteBehavior.SetNull);

        builder.HasOne(e => e.ApproverEmployee)
            .WithMany()
            .HasForeignKey(e => e.ApproverEmployeeId)
            .OnDelete(DeleteBehavior.SetNull);

        builder.Property(e => e.IsRequired).HasDefaultValue(true);
        builder.Property(e => e.IsActive).HasDefaultValue(true);
    }
}

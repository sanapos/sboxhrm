using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Configurations;

public class WorkTaskConfiguration : IEntityTypeConfiguration<WorkTask>
{
    public void Configure(EntityTypeBuilder<WorkTask> builder)
    {
        builder.ToTable("WorkTasks");
        
        builder.HasKey(e => e.Id);
        
        builder.Property(e => e.TaskCode)
            .HasMaxLength(20)
            .IsRequired();
        
        builder.Property(e => e.Title)
            .HasMaxLength(200)
            .IsRequired();
        
        builder.Property(e => e.Description)
            .HasMaxLength(4000);
        
        builder.Property(e => e.Tags)
            .HasMaxLength(500);
        
        builder.Property(e => e.CompletionNotes)
            .HasMaxLength(2000);
        
        // Indexes
        builder.HasIndex(e => e.StoreId)
            .HasDatabaseName("IX_WorkTasks_StoreId");
        
        builder.HasIndex(e => e.AssigneeId)
            .HasDatabaseName("IX_WorkTasks_AssigneeId");
        
        builder.HasIndex(e => e.AssignedById)
            .HasDatabaseName("IX_WorkTasks_AssignedById");
        
        builder.HasIndex(e => e.Status)
            .HasDatabaseName("IX_WorkTasks_Status");
        
        builder.HasIndex(e => e.DueDate)
            .HasDatabaseName("IX_WorkTasks_DueDate");
        
        builder.HasIndex(e => e.ParentTaskId)
            .HasDatabaseName("IX_WorkTasks_ParentTaskId");
        
        builder.HasIndex(e => new { e.StoreId, e.Status })
            .HasDatabaseName("IX_WorkTasks_Store_Status");
        
        builder.HasIndex(e => new { e.StoreId, e.AssigneeId, e.Status })
            .HasDatabaseName("IX_WorkTasks_Store_Assignee_Status");
        
        builder.HasIndex(e => e.TaskCode)
            .IsUnique()
            .HasDatabaseName("IX_WorkTasks_TaskCode");
        
        // Relationships
        builder.HasOne(e => e.Store)
            .WithMany()
            .HasForeignKey(e => e.StoreId)
            .OnDelete(DeleteBehavior.Restrict);
        
        builder.HasOne(e => e.AssignedBy)
            .WithMany()
            .HasForeignKey(e => e.AssignedById)
            .OnDelete(DeleteBehavior.Restrict);
        
        builder.HasOne(e => e.Assignee)
            .WithMany()
            .HasForeignKey(e => e.AssigneeId)
            .OnDelete(DeleteBehavior.SetNull);
        
        builder.HasOne(e => e.ParentTask)
            .WithMany(e => e.SubTasks)
            .HasForeignKey(e => e.ParentTaskId)
            .OnDelete(DeleteBehavior.SetNull);
        
        builder.HasMany(e => e.Comments)
            .WithOne(c => c.Task)
            .HasForeignKey(c => c.TaskId)
            .OnDelete(DeleteBehavior.Cascade);
        
        builder.HasMany(e => e.Attachments)
            .WithOne(a => a.Task)
            .HasForeignKey(a => a.TaskId)
            .OnDelete(DeleteBehavior.Cascade);
        
        builder.HasMany(e => e.TaskAssignees)
            .WithOne(ta => ta.Task)
            .HasForeignKey(ta => ta.TaskId)
            .OnDelete(DeleteBehavior.Cascade);
    }
}

public class TaskCommentConfiguration : IEntityTypeConfiguration<TaskComment>
{
    public void Configure(EntityTypeBuilder<TaskComment> builder)
    {
        builder.ToTable("TaskComments");
        
        builder.HasKey(e => e.Id);
        
        builder.Property(e => e.Content)
            .HasMaxLength(2000)
            .IsRequired();
        
        // Indexes
        builder.HasIndex(e => e.TaskId)
            .HasDatabaseName("IX_TaskComments_TaskId");
        
        builder.HasIndex(e => e.UserId)
            .HasDatabaseName("IX_TaskComments_UserId");
        
        // Relationships
        builder.HasOne(e => e.User)
            .WithMany()
            .HasForeignKey(e => e.UserId)
            .OnDelete(DeleteBehavior.Restrict);
        
        builder.HasOne(e => e.ParentComment)
            .WithMany(c => c.Replies)
            .HasForeignKey(e => e.ParentCommentId)
            .OnDelete(DeleteBehavior.Restrict);
    }
}

public class TaskAttachmentConfiguration : IEntityTypeConfiguration<TaskAttachment>
{
    public void Configure(EntityTypeBuilder<TaskAttachment> builder)
    {
        builder.ToTable("TaskAttachments");
        
        builder.HasKey(e => e.Id);
        
        builder.Property(e => e.FileName)
            .HasMaxLength(255)
            .IsRequired();
        
        builder.Property(e => e.FilePath)
            .HasMaxLength(500)
            .IsRequired();
        
        builder.Property(e => e.ContentType)
            .HasMaxLength(100);
        
        // Indexes
        builder.HasIndex(e => e.TaskId)
            .HasDatabaseName("IX_TaskAttachments_TaskId");
        
        // Relationships
        builder.HasOne(e => e.UploadedBy)
            .WithMany()
            .HasForeignKey(e => e.UploadedById)
            .OnDelete(DeleteBehavior.Restrict);
    }
}

public class TaskAssigneeConfiguration : IEntityTypeConfiguration<TaskAssignee>
{
    public void Configure(EntityTypeBuilder<TaskAssignee> builder)
    {
        builder.ToTable("TaskAssignees");
        
        builder.HasKey(e => e.Id);
        
        builder.Property(e => e.Role)
            .HasMaxLength(50);
        
        // Indexes
        builder.HasIndex(e => e.TaskId)
            .HasDatabaseName("IX_TaskAssignees_TaskId");
        
        builder.HasIndex(e => e.EmployeeId)
            .HasDatabaseName("IX_TaskAssignees_EmployeeId");
        
        builder.HasIndex(e => new { e.TaskId, e.EmployeeId })
            .IsUnique()
            .HasDatabaseName("IX_TaskAssignees_Task_Employee");
        
        // Relationships
        builder.HasOne(e => e.Employee)
            .WithMany()
            .HasForeignKey(e => e.EmployeeId)
            .OnDelete(DeleteBehavior.Cascade);
    }
}

public class TaskHistoryConfiguration : IEntityTypeConfiguration<TaskHistory>
{
    public void Configure(EntityTypeBuilder<TaskHistory> builder)
    {
        builder.ToTable("TaskHistories");
        
        builder.HasKey(e => e.Id);
        
        builder.Property(e => e.ChangeType)
            .HasMaxLength(50)
            .IsRequired();
        
        builder.Property(e => e.OldValue)
            .HasMaxLength(500);
        
        builder.Property(e => e.NewValue)
            .HasMaxLength(500);
        
        builder.Property(e => e.Description)
            .HasMaxLength(500);
        
        // Indexes
        builder.HasIndex(e => e.TaskId)
            .HasDatabaseName("IX_TaskHistories_TaskId");
        
        builder.HasIndex(e => e.UserId)
            .HasDatabaseName("IX_TaskHistories_UserId");
        
        builder.HasIndex(e => new { e.TaskId, e.CreatedAt })
            .HasDatabaseName("IX_TaskHistories_Task_CreatedAt");
        
        // Relationships
        builder.HasOne(e => e.Task)
            .WithMany()
            .HasForeignKey(e => e.TaskId)
            .OnDelete(DeleteBehavior.Cascade);
        
        builder.HasOne(e => e.User)
            .WithMany()
            .HasForeignKey(e => e.UserId)
            .OnDelete(DeleteBehavior.Restrict);
    }
}

public class TaskReminderConfiguration : IEntityTypeConfiguration<TaskReminder>
{
    public void Configure(EntityTypeBuilder<TaskReminder> builder)
    {
        builder.ToTable("TaskReminders");
        builder.HasKey(e => e.Id);
        builder.Property(e => e.Message).HasMaxLength(1000).IsRequired();

        builder.HasIndex(e => e.TaskId).HasDatabaseName("IX_TaskReminders_TaskId");
        builder.HasIndex(e => e.SentToId).HasDatabaseName("IX_TaskReminders_SentToId");

        builder.HasOne(e => e.Task).WithMany().HasForeignKey(e => e.TaskId).OnDelete(DeleteBehavior.Cascade);
        builder.HasOne(e => e.SentBy).WithMany().HasForeignKey(e => e.SentById).OnDelete(DeleteBehavior.Restrict);
        builder.HasOne(e => e.SentTo).WithMany().HasForeignKey(e => e.SentToId).OnDelete(DeleteBehavior.Restrict);
    }
}

public class TaskEvaluationConfiguration : IEntityTypeConfiguration<TaskEvaluation>
{
    public void Configure(EntityTypeBuilder<TaskEvaluation> builder)
    {
        builder.ToTable("TaskEvaluations");
        builder.HasKey(e => e.Id);
        builder.Property(e => e.Comment).HasMaxLength(2000);

        builder.HasIndex(e => e.TaskId).HasDatabaseName("IX_TaskEvaluations_TaskId");
        builder.HasIndex(e => new { e.TaskId, e.EvaluatorId }).IsUnique().HasDatabaseName("IX_TaskEvaluations_Task_Evaluator");

        builder.HasOne(e => e.Task).WithMany().HasForeignKey(e => e.TaskId).OnDelete(DeleteBehavior.Cascade);
        builder.HasOne(e => e.Evaluator).WithMany().HasForeignKey(e => e.EvaluatorId).OnDelete(DeleteBehavior.Restrict);
    }
}

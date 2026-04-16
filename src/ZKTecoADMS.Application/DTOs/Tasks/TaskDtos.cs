using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.DTOs.Tasks;

// =========== Task DTOs ===========

public class WorkTaskDto
{
    public Guid Id { get; set; }
    public string TaskCode { get; set; } = string.Empty;
    public string Title { get; set; } = string.Empty;
    public string? Description { get; set; }
    public TaskType TaskType { get; set; }
    public string TaskTypeName => TaskType.ToString();
    public TaskPriority Priority { get; set; }
    public string PriorityName => Priority.ToString();
    public WorkTaskStatus Status { get; set; }
    public string StatusName => Status.ToString();
    public int Progress { get; set; }
    
    public Guid StoreId { get; set; }
    public string? StoreName { get; set; }
    
    public Guid AssignedById { get; set; }
    public string? AssignedByName { get; set; }
    
    public Guid? AssigneeId { get; set; }
    public string? AssigneeName { get; set; }
    
    public DateTime? StartDate { get; set; }
    public DateTime? DueDate { get; set; }
    public DateTime? ActualStartDate { get; set; }
    public DateTime? CompletedDate { get; set; }
    
    public decimal? EstimatedHours { get; set; }
    public decimal? ActualHours { get; set; }
    
    public Guid? ParentTaskId { get; set; }
    public string? ParentTaskTitle { get; set; }
    
    public string? Tags { get; set; }
    public string? Checklist { get; set; }
    public string? CompletionNotes { get; set; }
    
    public bool IsOverdue => DueDate.HasValue && DueDate.Value < DateTime.Now && Status != WorkTaskStatus.Completed && Status != WorkTaskStatus.Cancelled;
    
    public int SubTaskCount { get; set; }
    public int CompletedSubTaskCount { get; set; }
    public int CommentCount { get; set; }
    public int AttachmentCount { get; set; }
    
    public List<TaskAssigneeDto>? Assignees { get; set; }
    public List<TaskCommentDto>? Comments { get; set; }
    public List<TaskAttachmentDto>? Attachments { get; set; }
    public List<WorkTaskDto>? SubTasks { get; set; }
    
    public DateTime CreatedAt { get; set; }
    public string? CreatedBy { get; set; }
    public DateTime? UpdatedAt { get; set; }
    public bool IsActive { get; set; }
}

public class TaskCommentDto
{
    public Guid Id { get; set; }
    public Guid TaskId { get; set; }
    public Guid UserId { get; set; }
    public string? UserName { get; set; }
    public string? UserAvatar { get; set; }
    public string Content { get; set; } = string.Empty;
    public Guid? ParentCommentId { get; set; }
    public DateTime CreatedAt { get; set; }
    public List<TaskCommentDto>? Replies { get; set; }
}

public class TaskAttachmentDto
{
    public Guid Id { get; set; }
    public Guid TaskId { get; set; }
    public Guid UploadedById { get; set; }
    public string? UploadedByName { get; set; }
    public string FileName { get; set; } = string.Empty;
    public string FilePath { get; set; } = string.Empty;
    public string? ContentType { get; set; }
    public long FileSize { get; set; }
    public DateTime CreatedAt { get; set; }
}

public class TaskAssigneeDto
{
    public Guid Id { get; set; }
    public Guid TaskId { get; set; }
    public Guid EmployeeId { get; set; }
    public string? EmployeeName { get; set; }
    public string? EmployeeCode { get; set; }
    public string? EmployeeAvatar { get; set; }
    public string? Role { get; set; }
    public DateTime AssignedAt { get; set; }
}

public class TaskHistoryDto
{
    public Guid Id { get; set; }
    public Guid TaskId { get; set; }
    public Guid UserId { get; set; }
    public string? UserName { get; set; }
    public string ChangeType { get; set; } = string.Empty;
    public string? OldValue { get; set; }
    public string? NewValue { get; set; }
    public string? Description { get; set; }
    public DateTime CreatedAt { get; set; }
}

// =========== Create/Update DTOs ===========

public class CreateTaskDto
{
    public string Title { get; set; } = string.Empty;
    public string? Description { get; set; }
    public TaskType TaskType { get; set; } = TaskType.Task;
    public TaskPriority Priority { get; set; } = TaskPriority.Medium;
    public Guid? AssigneeId { get; set; }
    public List<Guid>? AssigneeIds { get; set; }
    public DateTime? StartDate { get; set; }
    public DateTime? DueDate { get; set; }
    public decimal? EstimatedHours { get; set; }
    public Guid? ParentTaskId { get; set; }
    public string? Tags { get; set; }
    public string? Checklist { get; set; }
}

public class UpdateTaskDto
{
    public string? Title { get; set; }
    public string? Description { get; set; }
    public TaskType? TaskType { get; set; }
    public TaskPriority? Priority { get; set; }
    public WorkTaskStatus? Status { get; set; }
    public int? Progress { get; set; }
    public Guid? AssigneeId { get; set; }
    public DateTime? StartDate { get; set; }
    public DateTime? DueDate { get; set; }
    public decimal? EstimatedHours { get; set; }
    public decimal? ActualHours { get; set; }
    public string? Tags { get; set; }
    public string? Checklist { get; set; }
    public string? CompletionNotes { get; set; }
}

public class UpdateTaskStatusDto
{
    public WorkTaskStatus Status { get; set; }
    public int? Progress { get; set; }
    public string? CompletionNotes { get; set; }
}

public class UpdateTaskProgressDto
{
    public int Progress { get; set; }
    public string? Notes { get; set; }
}

public class AssignTaskDto
{
    public List<Guid> EmployeeIds { get; set; } = new();
    public string? Role { get; set; }
}

public class CreateCommentDto
{
    public string Content { get; set; } = string.Empty;
    public Guid? ParentCommentId { get; set; }
}

// =========== Query DTOs ===========

public class TaskQueryParams
{
    public int Page { get; set; } = 1;
    public int PageSize { get; set; } = 20;
    public string? Search { get; set; }
    public WorkTaskStatus? Status { get; set; }
    public TaskPriority? Priority { get; set; }
    public TaskType? TaskType { get; set; }
    public Guid? AssigneeId { get; set; }
    public Guid? AssignedById { get; set; }
    public DateTime? FromDate { get; set; }
    public DateTime? ToDate { get; set; }
    public bool? IsOverdue { get; set; }
    public Guid? ParentTaskId { get; set; }
    public string? SortBy { get; set; }
    public bool SortDesc { get; set; } = true;
}

// =========== Statistics DTOs ===========

public class TaskStatisticsDto
{
    public int TotalTasks { get; set; }
    public int TodoCount { get; set; }
    public int InProgressCount { get; set; }
    public int InReviewCount { get; set; }
    public int CompletedCount { get; set; }
    public int CancelledCount { get; set; }
    public int OnHoldCount { get; set; }
    public int OverdueCount { get; set; }
    public double CompletionRate { get; set; }
    public double AverageProgress { get; set; }
    
    public List<TasksByPriorityDto>? ByPriority { get; set; }
    public List<TasksByTypeDto>? ByType { get; set; }
    public List<TasksByAssigneeDto>? ByAssignee { get; set; }
}

public class TasksByPriorityDto
{
    public TaskPriority Priority { get; set; }
    public string PriorityName => Priority.ToString();
    public int Count { get; set; }
}

public class TasksByTypeDto
{
    public TaskType TaskType { get; set; }
    public string TypeName => TaskType.ToString();
    public int Count { get; set; }
}

public class TasksByAssigneeDto
{
    public Guid EmployeeId { get; set; }
    public string? EmployeeName { get; set; }
    public int TotalTasks { get; set; }
    public int CompletedTasks { get; set; }
    public int InProgressTasks { get; set; }
    public int OverdueTasks { get; set; }
}

// =========== Kanban Board DTOs ===========

public class KanbanBoardDto
{
    public List<KanbanColumnDto> Columns { get; set; } = new();
}

public class KanbanColumnDto
{
    public WorkTaskStatus Status { get; set; }
    public string StatusName => Status.ToString();
    public int TaskCount { get; set; }
    public List<WorkTaskDto> Tasks { get; set; } = new();
}

// =========== Batch Operation DTOs ===========

public class BatchUpdateStatusDto
{
    public List<Guid> TaskIds { get; set; } = new();
    public WorkTaskStatus Status { get; set; }
}

public class BatchAssignDto
{
    public List<Guid> TaskIds { get; set; } = new();
    public Guid AssigneeId { get; set; }
}

public class BatchDeleteDto
{
    public List<Guid> TaskIds { get; set; } = new();
}

// =========== Reminder DTOs ===========

public class TaskReminderDto
{
    public Guid Id { get; set; }
    public Guid TaskId { get; set; }
    public string? TaskTitle { get; set; }
    public string? TaskCode { get; set; }
    public Guid SentById { get; set; }
    public string? SentByName { get; set; }
    public Guid SentToId { get; set; }
    public string? SentToName { get; set; }
    public string Message { get; set; } = string.Empty;
    public int UrgencyLevel { get; set; }
    public bool IsRead { get; set; }
    public DateTime? ReadAt { get; set; }
    public DateTime CreatedAt { get; set; }
}

public class CreateReminderDto
{
    public Guid TaskId { get; set; }
    public Guid SentToId { get; set; }
    public string Message { get; set; } = string.Empty;
    public int UrgencyLevel { get; set; }
}

// =========== Evaluation DTOs ===========

public class TaskEvaluationDto
{
    public Guid Id { get; set; }
    public Guid TaskId { get; set; }
    public string? TaskTitle { get; set; }
    public Guid EvaluatorId { get; set; }
    public string? EvaluatorName { get; set; }
    public int QualityScore { get; set; }
    public int TimelinessScore { get; set; }
    public int OverallScore { get; set; }
    public string? Comment { get; set; }
    public DateTime CreatedAt { get; set; }
}

public class CreateEvaluationDto
{
    public int QualityScore { get; set; }
    public int TimelinessScore { get; set; }
    public int OverallScore { get; set; }
    public string? Comment { get; set; }
}

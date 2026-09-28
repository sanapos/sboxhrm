using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.DTOs.Tasks;

// =========== Công việc v2: dự án, giai đoạn, checklist, thống kê ===========

public class TaskStageDto
{
    public string Key { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string? Color { get; set; }
    public bool Done { get; set; }
}

public class TaskProjectDto
{
    public Guid Id { get; set; }
    public string Code { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string? Description { get; set; }
    public string? IndustryKey { get; set; }
    public string? Color { get; set; }
    public TaskProjectStatus Status { get; set; }
    public Guid? OwnerEmployeeId { get; set; }
    public string? OwnerName { get; set; }
    public Guid? BranchId { get; set; }
    public string? CustomerName { get; set; }
    public string? CustomerPhone { get; set; }
    public string? Address { get; set; }
    public decimal? Budget { get; set; }
    public DateTime? StartDate { get; set; }
    public DateTime? DueDate { get; set; }
    public DateTime? CompletedAt { get; set; }
    public List<TaskStageDto> Stages { get; set; } = new();
    public DateTime CreatedAt { get; set; }

    // Tiến độ
    public int TaskCount { get; set; }
    public int DoneCount { get; set; }
    public int InProgressCount { get; set; }
    public int OverdueCount { get; set; }
    /// <summary>% hoàn thành (trung bình tiến độ việc, việc xong = 100, bỏ việc hủy)</summary>
    public int Progress { get; set; }
    public bool IsOverdue { get; set; }
    public Dictionary<string, int>? StageCounts { get; set; }
}

public class SaveTaskProjectDto
{
    public string Name { get; set; } = string.Empty;
    public string? Code { get; set; }
    public string? Description { get; set; }
    public string? IndustryKey { get; set; }
    public string? Color { get; set; }
    public TaskProjectStatus? Status { get; set; }
    public Guid? OwnerEmployeeId { get; set; }
    public Guid? BranchId { get; set; }
    public string? CustomerName { get; set; }
    public string? CustomerPhone { get; set; }
    public string? Address { get; set; }
    public decimal? Budget { get; set; }
    public DateTime? StartDate { get; set; }
    public DateTime? DueDate { get; set; }
    public List<TaskStageDto>? Stages { get; set; }
    /// <summary>Tạo sẵn việc từ các mẫu của gói ngành (khi tạo mới)</summary>
    public bool CreateTasksFromPack { get; set; }
}

public class TaskIndustryPackTemplateDto
{
    public string Name { get; set; } = string.Empty;
    public TaskType TaskType { get; set; }
    public string? StageKey { get; set; }
    public decimal? EstimatedHours { get; set; }
    public List<string> Checklist { get; set; } = new();
    public int PhotoItems { get; set; }
    public TaskRecurrenceType RecurrenceType { get; set; }
    public string? RecurrenceDays { get; set; }
    public string? RecurrenceTime { get; set; }
}

public class TaskIndustryPackDto
{
    public string Key { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string Icon { get; set; } = string.Empty;
    public string Description { get; set; } = string.Empty;
    public string ProjectLabel { get; set; } = string.Empty;
    public string Color { get; set; } = string.Empty;
    public List<TaskStageDto> Stages { get; set; } = new();
    public List<TaskIndustryPackTemplateDto> Templates { get; set; } = new();
    public int InstalledTemplates { get; set; }
}

public class InstallIndustryPackDto
{
    /// <summary>Bật lịch lặp cho mẫu việc định kỳ (vẫn cần chọn người nhận mới chạy)</summary>
    public bool EnableRecurring { get; set; } = true;
    /// <summary>Nhân viên nhận các việc định kỳ</summary>
    public List<Guid>? RecurringAssigneeIds { get; set; }
}

public class InstallIndustryPackResultDto
{
    public int CreatedTemplates { get; set; }
    public int SkippedTemplates { get; set; }
    public int RecurringTemplates { get; set; }
}

public class MoveTaskStageDto
{
    public string StageKey { get; set; } = string.Empty;
}

public class ToggleChecklistItemDto
{
    public bool Done { get; set; }
    public string? PhotoUrl { get; set; }
    public string? Note { get; set; }
}

public class TaskWorkloadDto
{
    public Guid EmployeeId { get; set; }
    public string EmployeeName { get; set; } = string.Empty;
    public string? EmployeeCode { get; set; }
    public int Open { get; set; }
    public int InProgress { get; set; }
    public int Overdue { get; set; }
    public int DueSoon { get; set; }
    public int CompletedInRange { get; set; }
    public int CompletedOnTime { get; set; }
    /// <summary>% đúng hạn trong kỳ (việc xong có hạn chót)</summary>
    public double OnTimeRate { get; set; }
    public decimal OpenEstimatedHours { get; set; }
}

public class TaskTimelineItemDto
{
    public Guid Id { get; set; }
    public string TaskCode { get; set; } = string.Empty;
    public string Title { get; set; } = string.Empty;
    public WorkTaskStatus Status { get; set; }
    public TaskPriority Priority { get; set; }
    public int Progress { get; set; }
    public DateTime? StartDate { get; set; }
    public DateTime? DueDate { get; set; }
    public DateTime? CompletedDate { get; set; }
    public DateTime CreatedAt { get; set; }
    public string? StageKey { get; set; }
    public Guid? ProjectId { get; set; }
    public string? ProjectName { get; set; }
    public Guid? ParentTaskId { get; set; }
    public string? AssigneeName { get; set; }
    public List<Guid> BlockedBy { get; set; } = new();
}

public class TaskInsightDayDto
{
    public DateTime Date { get; set; }
    public int Created { get; set; }
    public int Completed { get; set; }
    public int CompletedLate { get; set; }
}

public class TaskInsightsDto
{
    public int Total { get; set; }
    public int Open { get; set; }
    public int InProgress { get; set; }
    public int PendingAcceptance { get; set; }
    public int InReview { get; set; }
    public int Overdue { get; set; }
    public int DueToday { get; set; }
    public int CompletedInRange { get; set; }
    public int CompletedOnTime { get; set; }
    public double OnTimeRate { get; set; }
    /// <summary>Thời gian TB từ lúc tạo đến lúc xong (giờ)</summary>
    public double AvgCycleHours { get; set; }
    public int CompletedPrevRange { get; set; }
    public List<TaskInsightDayDto> ByDay { get; set; } = new();
    public Dictionary<string, int> ByStatus { get; set; } = new();
    public Dictionary<string, int> ByType { get; set; } = new();
    public int ActiveProjects { get; set; }
}

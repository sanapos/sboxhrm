using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.DTOs.Tasks;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
public class TasksController(
    ZKTecoDbContext dbContext,
    ISystemNotificationService notificationService
) : AuthenticatedControllerBase
{
    private readonly ZKTecoDbContext _dbContext = dbContext;

    /// <summary>
    /// Resolve Employee.Id → ApplicationUser.Id for notification targeting
    /// </summary>
    private async Task<Guid?> ResolveUserIdFromEmployeeId(Guid employeeId)
    {
        var emp = await _dbContext.Employees
            .Where(e => e.Id == employeeId)
            .Select(e => e.ApplicationUserId)
            .FirstOrDefaultAsync();
        return emp;
    }

    #region Task CRUD

    /// <summary>
    /// Láº¥y danh sÃ¡ch cÃ´ng viá»‡c
    /// </summary>
    [HttpGet]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<PagedResult<WorkTaskDto>>>> GetTasks(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20,
        [FromQuery] string? search = null,
        [FromQuery] WorkTaskStatus? status = null,
        [FromQuery] TaskPriority? priority = null,
        [FromQuery] TaskType? taskType = null,
        [FromQuery] Guid? assigneeId = null,
        [FromQuery] Guid? assignedById = null,
        [FromQuery] DateTime? fromDate = null,
        [FromQuery] DateTime? toDate = null,
        [FromQuery] bool? isOverdue = null,
        [FromQuery] Guid? parentTaskId = null,
        [FromQuery] string? sortBy = "CreatedAt",
        [FromQuery] bool sortDesc = true)
    {
        var query = _dbContext.WorkTasks
            .Where(t => t.StoreId == RequiredStoreId && t.IsActive);

        // Filters
        if (!string.IsNullOrEmpty(search))
        {
            var searchPattern = $"%{search}%";
            query = query.Where(t => 
                EF.Functions.ILike(t.Title, searchPattern) ||
                EF.Functions.ILike(t.TaskCode, searchPattern) ||
                (t.Description != null && EF.Functions.ILike(t.Description, searchPattern)));
        }

        if (status.HasValue)
            query = query.Where(t => t.Status == status.Value);

        if (priority.HasValue)
            query = query.Where(t => t.Priority == priority.Value);

        if (taskType.HasValue)
            query = query.Where(t => t.TaskType == taskType.Value);

        if (assigneeId.HasValue)
            query = query.Where(t => t.AssigneeId == assigneeId.Value || 
                t.TaskAssignees!.Any(ta => ta.EmployeeId == assigneeId.Value));

        if (assignedById.HasValue)
            query = query.Where(t => t.AssignedById == assignedById.Value);

        if (fromDate.HasValue)
            query = query.Where(t => t.DueDate >= fromDate.Value || t.StartDate >= fromDate.Value);

        if (toDate.HasValue)
            query = query.Where(t => t.DueDate <= toDate.Value || t.StartDate <= toDate.Value);

        if (isOverdue == true)
            query = query.Where(t => t.DueDate < DateTime.Now && 
                t.Status != WorkTaskStatus.Completed && 
                t.Status != WorkTaskStatus.Cancelled);

        if (parentTaskId.HasValue)
            query = query.Where(t => t.ParentTaskId == parentTaskId.Value);
        else
            query = query.Where(t => t.ParentTaskId == null); // Only top-level tasks by default

        // Sorting
        query = sortBy?.ToLower() switch
        {
            "title" => sortDesc ? query.OrderByDescending(t => t.Title) : query.OrderBy(t => t.Title),
            "duedate" => sortDesc ? query.OrderByDescending(t => t.DueDate) : query.OrderBy(t => t.DueDate),
            "priority" => sortDesc ? query.OrderByDescending(t => t.Priority) : query.OrderBy(t => t.Priority),
            "status" => sortDesc ? query.OrderByDescending(t => t.Status) : query.OrderBy(t => t.Status),
            "progress" => sortDesc ? query.OrderByDescending(t => t.Progress) : query.OrderBy(t => t.Progress),
            _ => sortDesc ? query.OrderByDescending(t => t.CreatedAt) : query.OrderBy(t => t.CreatedAt)
        };

        var totalCount = await query.CountAsync();
        var tasks = await query
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(t => new WorkTaskDto
            {
                Id = t.Id,
                TaskCode = t.TaskCode,
                Title = t.Title,
                Description = t.Description,
                TaskType = t.TaskType,
                Priority = t.Priority,
                Status = t.Status,
                Progress = t.Progress,
                StoreId = t.StoreId,
                AssignedById = t.AssignedById,
                AssignedByName = t.AssignedBy != null ? t.AssignedBy.UserName : null,
                AssigneeId = t.AssigneeId,
                AssigneeName = t.Assignee != null ? t.Assignee.LastName + " " + t.Assignee.FirstName : null,
                StartDate = t.StartDate,
                DueDate = t.DueDate,
                ActualStartDate = t.ActualStartDate,
                CompletedDate = t.CompletedDate,
                EstimatedHours = t.EstimatedHours,
                ActualHours = t.ActualHours,
                ParentTaskId = t.ParentTaskId,
                Tags = t.Tags,
                Checklist = t.Checklist,
                CreatedAt = t.CreatedAt,
                CreatedBy = t.CreatedBy,
                UpdatedAt = t.UpdatedAt,
                IsActive = t.IsActive,
                Assignees = t.TaskAssignees != null ? t.TaskAssignees.Select(ta => new TaskAssigneeDto
                {
                    Id = ta.Id,
                    TaskId = ta.TaskId,
                    EmployeeId = ta.EmployeeId,
                    EmployeeName = ta.Employee != null ? ta.Employee.LastName + " " + ta.Employee.FirstName : null,
                    EmployeeCode = ta.Employee != null ? ta.Employee.EmployeeCode : null,
                    Role = ta.Role,
                    AssignedAt = ta.AssignedAt
                }).ToList() : null
            })
            .ToListAsync();

        var taskDtos = tasks;

        // Batch load counts in single queries instead of N+1
        var taskIds = taskDtos.Select(d => d.Id).ToList();
        
        var subTaskCounts = await _dbContext.WorkTasks
            .Where(t => t.ParentTaskId != null && taskIds.Contains(t.ParentTaskId.Value) && t.IsActive)
            .GroupBy(t => t.ParentTaskId!.Value)
            .Select(g => new { ParentId = g.Key, Total = g.Count(), Completed = g.Count(t => t.Status == WorkTaskStatus.Completed) })
            .ToDictionaryAsync(x => x.ParentId, x => new { x.Total, x.Completed });

        var commentCounts = await _dbContext.TaskComments
            .Where(c => taskIds.Contains(c.TaskId))
            .GroupBy(c => c.TaskId)
            .Select(g => new { TaskId = g.Key, Count = g.Count() })
            .ToDictionaryAsync(x => x.TaskId, x => x.Count);

        var attachmentCounts = await _dbContext.TaskAttachments
            .Where(a => taskIds.Contains(a.TaskId))
            .GroupBy(a => a.TaskId)
            .Select(g => new { TaskId = g.Key, Count = g.Count() })
            .ToDictionaryAsync(x => x.TaskId, x => x.Count);

        foreach (var dto in taskDtos)
        {
            if (subTaskCounts.TryGetValue(dto.Id, out var sc))
            {
                dto.SubTaskCount = sc.Total;
                dto.CompletedSubTaskCount = sc.Completed;
            }
            dto.CommentCount = commentCounts.GetValueOrDefault(dto.Id);
            dto.AttachmentCount = attachmentCounts.GetValueOrDefault(dto.Id);
        }

        var result = new PagedResult<WorkTaskDto>
        {
            Items = taskDtos,
            TotalCount = totalCount,
            PageNumber = page,
            PageSize = pageSize
        };

        return Ok(AppResponse<PagedResult<WorkTaskDto>>.Success(result));
    }

    /// <summary>
    /// Láº¥y cÃ´ng viá»‡c cá»§a tÃ´i
    /// </summary>
    [HttpGet("my")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<PagedResult<WorkTaskDto>>>> GetMyTasks(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20,
        [FromQuery] WorkTaskStatus? status = null,
        [FromQuery] TaskPriority? priority = null)
    {
        // Get employee ID for current user
        var employee = await _dbContext.Employees
            .FirstOrDefaultAsync(e => e.ApplicationUserId == CurrentUserId && e.StoreId == RequiredStoreId);

        if (employee == null)
            return Ok(AppResponse<PagedResult<WorkTaskDto>>.Error("Employee not found"));

        var query = _dbContext.WorkTasks
            .Where(t => t.StoreId == RequiredStoreId && t.IsActive &&
                (t.AssigneeId == employee.Id || t.TaskAssignees!.Any(ta => ta.EmployeeId == employee.Id)));

        if (status.HasValue)
            query = query.Where(t => t.Status == status.Value);

        if (priority.HasValue)
            query = query.Where(t => t.Priority == priority.Value);

        query = query.OrderByDescending(t => t.Priority).ThenByDescending(t => t.CreatedAt);

        var totalCount = await query.CountAsync();
        var tasks = await query
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(t => new WorkTaskDto
            {
                Id = t.Id,
                TaskCode = t.TaskCode,
                Title = t.Title,
                Description = t.Description,
                TaskType = t.TaskType,
                Priority = t.Priority,
                Status = t.Status,
                Progress = t.Progress,
                StoreId = t.StoreId,
                AssignedById = t.AssignedById,
                AssignedByName = t.AssignedBy != null ? t.AssignedBy.UserName : null,
                AssigneeId = t.AssigneeId,
                AssigneeName = t.Assignee != null ? t.Assignee.LastName + " " + t.Assignee.FirstName : null,
                StartDate = t.StartDate,
                DueDate = t.DueDate,
                ActualStartDate = t.ActualStartDate,
                CompletedDate = t.CompletedDate,
                EstimatedHours = t.EstimatedHours,
                ActualHours = t.ActualHours,
                ParentTaskId = t.ParentTaskId,
                Tags = t.Tags,
                Checklist = t.Checklist,
                CreatedAt = t.CreatedAt,
                CreatedBy = t.CreatedBy,
                UpdatedAt = t.UpdatedAt,
                IsActive = t.IsActive,
                Assignees = t.TaskAssignees != null ? t.TaskAssignees.Select(ta => new TaskAssigneeDto
                {
                    Id = ta.Id,
                    TaskId = ta.TaskId,
                    EmployeeId = ta.EmployeeId,
                    EmployeeName = ta.Employee != null ? ta.Employee.LastName + " " + ta.Employee.FirstName : null,
                    EmployeeCode = ta.Employee != null ? ta.Employee.EmployeeCode : null,
                    Role = ta.Role,
                    AssignedAt = ta.AssignedAt
                }).ToList() : null
            })
            .ToListAsync();

        var taskDtos = tasks;

        var result = new PagedResult<WorkTaskDto>
        {
            Items = taskDtos,
            TotalCount = totalCount,
            PageNumber = page,
            PageSize = pageSize
        };

        return Ok(AppResponse<PagedResult<WorkTaskDto>>.Success(result));
    }

    /// <summary>
    /// Láº¥y chi tiáº¿t cÃ´ng viá»‡c
    /// </summary>
    [HttpGet("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<WorkTaskDto>>> GetTaskById(Guid id)
    {
        var task = await _dbContext.WorkTasks
            .Include(t => t.Store)
            .Include(t => t.Assignee)
            .Include(t => t.AssignedBy)
            .Include(t => t.ParentTask)
            .Include(t => t.TaskAssignees!)
                .ThenInclude(ta => ta.Employee)
            .Include(t => t.Comments!)
                .ThenInclude(c => c.User)
            .Include(t => t.Attachments!)
                .ThenInclude(a => a.UploadedBy)
            .Include(t => t.SubTasks!.Where(st => st.IsActive))
            .FirstOrDefaultAsync(t => t.Id == id && t.StoreId == RequiredStoreId);

        if (task == null)
            return Ok(AppResponse<WorkTaskDto>.Error("Task not found"));

        var dto = MapToDto(task, includeDetails: true);
        return Ok(AppResponse<WorkTaskDto>.Success(dto));
    }

    /// <summary>
    /// Táº¡o cÃ´ng viá»‡c má»›i
    /// </summary>
    [HttpPost]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<WorkTaskDto>>> CreateTask([FromBody] CreateTaskDto request)
    {
        // Generate task code
        var taskCount = await _dbContext.WorkTasks.CountAsync(t => t.StoreId == RequiredStoreId);
        var taskCode = $"TASK-{(taskCount + 1):D4}";

        var task = new WorkTask
        {
            Id = Guid.NewGuid(),
            TaskCode = taskCode,
            Title = request.Title,
            Description = request.Description,
            TaskType = request.TaskType,
            Priority = request.Priority,
            Status = WorkTaskStatus.Todo,
            Progress = 0,
            StoreId = RequiredStoreId,
            AssignedById = CurrentUserId,
            AssigneeId = request.AssigneeId,
            StartDate = request.StartDate,
            DueDate = request.DueDate,
            EstimatedHours = request.EstimatedHours,
            ParentTaskId = request.ParentTaskId,
            Tags = request.Tags,
            Checklist = request.Checklist,
            IsActive = true,
            CreatedBy = CurrentUserEmail
        };

        _dbContext.WorkTasks.Add(task);

        // Add multiple assignees if provided
        if (request.AssigneeIds?.Any() == true)
        {
            foreach (var employeeId in request.AssigneeIds)
            {
                _dbContext.TaskAssignees.Add(new TaskAssignee
                {
                    Id = Guid.NewGuid(),
                    TaskId = task.Id,
                    EmployeeId = employeeId,
                    AssignedAt = DateTime.Now
                });
            }
        }

        // Add history
        _dbContext.TaskHistories.Add(new TaskHistory
        {
            Id = Guid.NewGuid(),
            TaskId = task.Id,
            UserId = CurrentUserId,
            ChangeType = "Created",
            NewValue = task.Title,
            Description = $"Task created by {CurrentUserEmail}"
        });

        await _dbContext.SaveChangesAsync();

        // Reload with includes
        var createdTask = await _dbContext.WorkTasks
            .Include(t => t.Assignee)
            .Include(t => t.AssignedBy)
            .FirstOrDefaultAsync(t => t.Id == task.Id);

        try
        {
            // Resolve Employee.Id → ApplicationUser.Id for notifications
            if (task.AssigneeId.HasValue)
            {
                var userId = await ResolveUserIdFromEmployeeId(task.AssigneeId.Value);
                if (userId.HasValue)
                {
                    await notificationService.CreateAndSendAsync(
                        userId.Value, NotificationType.Info,
                        "Công việc mới",
                        $"Bạn được giao công việc mới: {task.Title}",
                        relatedEntityId: task.Id, relatedEntityType: "WorkTask",
                        fromUserId: CurrentUserId, categoryCode: "task", storeId: RequiredStoreId);
                }
            }
            if (request.AssigneeIds?.Any() == true)
            {
                foreach (var empId in request.AssigneeIds.Where(id => id != task.AssigneeId))
                {
                    var userId = await ResolveUserIdFromEmployeeId(empId);
                    if (userId.HasValue)
                    {
                        await notificationService.CreateAndSendAsync(
                            userId.Value, NotificationType.Info,
                            "Công việc mới",
                            $"Bạn được giao công việc mới: {task.Title}",
                            relatedEntityId: task.Id, relatedEntityType: "WorkTask",
                            fromUserId: CurrentUserId, categoryCode: "task", storeId: RequiredStoreId);
                    }
                }
            }
        }
        catch { /* Notification failure should not affect main operation */ }

        return Ok(AppResponse<WorkTaskDto>.Success(MapToDto(createdTask!)));
    }

    /// <summary>
    /// Cáº­p nháº­t cÃ´ng viá»‡c
    /// </summary>
    [HttpPut("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<WorkTaskDto>>> UpdateTask(Guid id, [FromBody] UpdateTaskDto request)
    {
        var task = await _dbContext.WorkTasks
            .AsTracking()
            .FirstOrDefaultAsync(t => t.Id == id && t.StoreId == RequiredStoreId);

        if (task == null)
            return Ok(AppResponse<WorkTaskDto>.Error("Task not found"));

        var histories = new List<TaskHistory>();

        // Track changes
        if (request.Title != null && request.Title != task.Title)
        {
            histories.Add(CreateHistory(task.Id, "TitleChanged", task.Title, request.Title));
            task.Title = request.Title;
        }

        if (request.Description != null)
            task.Description = request.Description;

        if (request.TaskType.HasValue && request.TaskType.Value != task.TaskType)
        {
            histories.Add(CreateHistory(task.Id, "TypeChanged", task.TaskType.ToString(), request.TaskType.Value.ToString()));
            task.TaskType = request.TaskType.Value;
        }

        if (request.Priority.HasValue && request.Priority.Value != task.Priority)
        {
            histories.Add(CreateHistory(task.Id, "PriorityChanged", task.Priority.ToString(), request.Priority.Value.ToString()));
            task.Priority = request.Priority.Value;
        }

        if (request.Status.HasValue && request.Status.Value != task.Status)
        {
            histories.Add(CreateHistory(task.Id, "StatusChanged", task.Status.ToString(), request.Status.Value.ToString()));
            task.Status = request.Status.Value;
            
            if (request.Status.Value == WorkTaskStatus.InProgress && task.ActualStartDate == null)
                task.ActualStartDate = DateTime.Now;
            
            if (request.Status.Value == WorkTaskStatus.Completed)
                task.CompletedDate = DateTime.Now;
        }

        if (request.Progress.HasValue && request.Progress.Value != task.Progress)
        {
            histories.Add(CreateHistory(task.Id, "ProgressUpdated", task.Progress.ToString(), request.Progress.Value.ToString()));
            task.Progress = request.Progress.Value;
        }

        Guid? oldAssigneeId = null;
        if (request.AssigneeId.HasValue && request.AssigneeId != task.AssigneeId)
        {
            oldAssigneeId = task.AssigneeId;
            histories.Add(CreateHistory(task.Id, "AssigneeChanged", task.AssigneeId?.ToString(), request.AssigneeId.Value.ToString()));
            task.AssigneeId = request.AssigneeId;
        }

        task.StartDate = request.StartDate ?? task.StartDate;
        task.DueDate = request.DueDate ?? task.DueDate;
        task.EstimatedHours = request.EstimatedHours ?? task.EstimatedHours;
        task.ActualHours = request.ActualHours ?? task.ActualHours;
        task.Tags = request.Tags ?? task.Tags;
        task.Checklist = request.Checklist ?? task.Checklist;
        task.CompletionNotes = request.CompletionNotes ?? task.CompletionNotes;

        task.UpdatedAt = DateTime.Now;
        task.UpdatedBy = CurrentUserEmail;

        if (histories.Any())
            _dbContext.TaskHistories.AddRange(histories);

        await _dbContext.SaveChangesAsync();

        // Notify new assignee when task is reassigned
        try
        {
            if (oldAssigneeId.HasValue && task.AssigneeId.HasValue)
            {
                var newAssigneeUserId = await ResolveUserIdFromEmployeeId(task.AssigneeId.Value);
                if (newAssigneeUserId.HasValue && newAssigneeUserId.Value != CurrentUserId)
                {
                    await notificationService.CreateAndSendAsync(
                        newAssigneeUserId.Value, NotificationType.Info,
                        "Công việc mới được giao",
                        $"Bạn được giao công việc: {task.Title}",
                        relatedEntityId: task.Id, relatedEntityType: "WorkTask",
                        fromUserId: CurrentUserId, categoryCode: "task", storeId: RequiredStoreId);
                }
            }
        }
        catch { /* Notification failure should not affect main operation */ }

        var updatedTask = await _dbContext.WorkTasks
            .Include(t => t.Assignee)
            .Include(t => t.AssignedBy)
            .FirstOrDefaultAsync(t => t.Id == task.Id);

        return Ok(AppResponse<WorkTaskDto>.Success(MapToDto(updatedTask!)));
    }

    /// <summary>
    /// Cáº­p nháº­t tráº¡ng thÃ¡i cÃ´ng viá»‡c
    /// </summary>
    [HttpPatch("{id}/status")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<WorkTaskDto>>> UpdateTaskStatus(Guid id, [FromBody] UpdateTaskStatusDto request)
    {
        var task = await _dbContext.WorkTasks
            .AsTracking()
            .FirstOrDefaultAsync(t => t.Id == id && t.StoreId == RequiredStoreId);

        if (task == null)
            return Ok(AppResponse<WorkTaskDto>.Error("Task not found"));

        var oldStatus = task.Status;
        task.Status = request.Status;

        if (request.Progress.HasValue)
            task.Progress = request.Progress.Value;

        if (!string.IsNullOrEmpty(request.CompletionNotes))
            task.CompletionNotes = request.CompletionNotes;

        if (request.Status == WorkTaskStatus.InProgress && task.ActualStartDate == null)
            task.ActualStartDate = DateTime.Now;

        if (request.Status == WorkTaskStatus.Completed)
        {
            task.CompletedDate = DateTime.Now;
            task.Progress = 100;
        }

        task.UpdatedAt = DateTime.Now;
        task.UpdatedBy = CurrentUserEmail;

        _dbContext.TaskHistories.Add(CreateHistory(task.Id, "StatusChanged", oldStatus.ToString(), request.Status.ToString()));

        await _dbContext.SaveChangesAsync();

        var updatedTask = await _dbContext.WorkTasks
            .Include(t => t.Assignee)
            .Include(t => t.AssignedBy)
            .FirstOrDefaultAsync(t => t.Id == task.Id);

        try
        {
            var statusText = request.Status switch
            {
                WorkTaskStatus.InProgress => "Đang thực hiện",
                WorkTaskStatus.InReview => "Đang review",
                WorkTaskStatus.Completed => "Hoàn thành",
                WorkTaskStatus.Cancelled => "Đã hủy",
                WorkTaskStatus.OnHold => "Tạm hoãn",
                _ => request.Status.ToString()
            };
            if (task.AssigneeId.HasValue && task.AssigneeId.Value != CurrentUserId)
            {
                var assigneeUserId = await ResolveUserIdFromEmployeeId(task.AssigneeId.Value);
                if (assigneeUserId.HasValue && assigneeUserId.Value != CurrentUserId)
                {
                    await notificationService.CreateAndSendAsync(
                        assigneeUserId.Value, NotificationType.Info,
                        "Trạng thái công việc thay đổi",
                        $"Công việc \"{task.Title}\" đã chuyển sang: {statusText}",
                        relatedEntityId: task.Id, relatedEntityType: "WorkTask",
                        fromUserId: CurrentUserId, categoryCode: "task", storeId: RequiredStoreId);
                }
            }
            if (request.Status == WorkTaskStatus.Completed && task.AssignedById != Guid.Empty && task.AssignedById != CurrentUserId)
            {
                await notificationService.CreateAndSendAsync(
                    task.AssignedById, NotificationType.Success,
                    "Công việc hoàn thành",
                    $"Công việc \"{task.Title}\" đã được hoàn thành",
                    relatedEntityId: task.Id, relatedEntityType: "WorkTask",
                    fromUserId: CurrentUserId, categoryCode: "task", storeId: RequiredStoreId);
            }
        }
        catch { /* Notification failure should not affect main operation */ }

        return Ok(AppResponse<WorkTaskDto>.Success(MapToDto(updatedTask!)));
    }

    /// <summary>
    /// Cáº­p nháº­t tiáº¿n Ä‘á»™
    /// </summary>
    [HttpPatch("{id}/progress")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<WorkTaskDto>>> UpdateTaskProgress(Guid id, [FromBody] UpdateTaskProgressDto request)
    {
        var task = await _dbContext.WorkTasks
            .AsTracking()
            .FirstOrDefaultAsync(t => t.Id == id && t.StoreId == RequiredStoreId);

        if (task == null)
            return Ok(AppResponse<WorkTaskDto>.Error("Task not found"));

        var oldProgress = task.Progress;
        task.Progress = Math.Clamp(request.Progress, 0, 100);

        if (!string.IsNullOrEmpty(request.Notes))
            task.CompletionNotes = request.Notes;

        // Auto-update status based on progress
        if (task.Progress == 100 && task.Status != WorkTaskStatus.Completed)
        {
            task.Status = WorkTaskStatus.Completed;
            task.CompletedDate = DateTime.Now;
        }
        else if (task.Progress > 0 && task.Status == WorkTaskStatus.Todo)
        {
            task.Status = WorkTaskStatus.InProgress;
            task.ActualStartDate ??= DateTime.Now;
        }

        task.UpdatedAt = DateTime.Now;
        task.UpdatedBy = CurrentUserEmail;

        _dbContext.TaskHistories.Add(CreateHistory(task.Id, "ProgressUpdated", oldProgress.ToString(), task.Progress.ToString()));

        // Auto-create progress update comment
        if (!string.IsNullOrEmpty(request.Notes) || !string.IsNullOrEmpty(request.ImageUrls) || !string.IsNullOrEmpty(request.LinkUrls))
        {
            _dbContext.TaskComments.Add(new TaskComment
            {
                Id = Guid.NewGuid(),
                TaskId = id,
                UserId = CurrentUserId,
                Content = request.Notes ?? $"Cập nhật tiến độ: {oldProgress}% → {task.Progress}%",
                CommentType = 1,
                ImageUrls = request.ImageUrls,
                LinkUrls = request.LinkUrls,
                ProgressSnapshot = task.Progress
            });
        }

        await _dbContext.SaveChangesAsync();

        // Notify task owner about progress
        try
        {
            if (task.AssignedById != Guid.Empty && task.AssignedById != CurrentUserId)
            {
                await notificationService.CreateAndSendAsync(
                    task.AssignedById, NotificationType.Info,
                    "Cập nhật tiến độ",
                    $"Công việc \"{task.Title}\" đã cập nhật tiến độ: {task.Progress}%",
                    relatedEntityId: task.Id, relatedEntityType: "WorkTask",
                    fromUserId: CurrentUserId, categoryCode: "task", storeId: RequiredStoreId);
            }
        }
        catch { /* Notification failure should not affect main operation */ }

        var updatedTask = await _dbContext.WorkTasks
            .Include(t => t.Assignee)
            .Include(t => t.AssignedBy)
            .FirstOrDefaultAsync(t => t.Id == task.Id);

        return Ok(AppResponse<WorkTaskDto>.Success(MapToDto(updatedTask!)));
    }

    /// <summary>
    /// XÃ³a cÃ´ng viá»‡c (soft delete)
    /// </summary>
    [HttpDelete("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<bool>>> DeleteTask(Guid id)
    {
        var task = await _dbContext.WorkTasks
            .AsTracking()
            .FirstOrDefaultAsync(t => t.Id == id && t.StoreId == RequiredStoreId);

        if (task == null)
            return Ok(AppResponse<bool>.Error("Task not found"));

        task.IsActive = false;
        task.Deleted = DateTime.Now;
        task.DeletedBy = CurrentUserEmail;

        await _dbContext.SaveChangesAsync();

        // Notify assignee about task deletion
        try
        {
            if (task.AssigneeId.HasValue)
            {
                var assigneeUserId = await ResolveUserIdFromEmployeeId(task.AssigneeId.Value);
                if (assigneeUserId.HasValue && assigneeUserId.Value != CurrentUserId)
                {
                    await notificationService.CreateAndSendAsync(
                        assigneeUserId.Value, NotificationType.Warning,
                        "Công việc đã bị xóa",
                        $"Công việc \"{task.Title}\" đã bị xóa",
                        relatedEntityId: task.Id, relatedEntityType: "WorkTask",
                        fromUserId: CurrentUserId, categoryCode: "task", storeId: RequiredStoreId);
                }
            }
        }
        catch { /* Notification failure should not affect main operation */ }

        return Ok(AppResponse<bool>.Success(true));
    }

    #endregion

    #region Batch Operations

    /// <summary>
    /// Cáº­p nháº­t tráº¡ng thÃ¡i hÃ ng loáº¡t
    /// </summary>
    [HttpPost("batch/status")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<int>>> BatchUpdateStatus([FromBody] BatchUpdateStatusDto request)
    {
        var tasks = await _dbContext.WorkTasks
            .AsTracking()
            .Where(t => request.TaskIds.Contains(t.Id) && t.StoreId == RequiredStoreId && t.IsActive)
            .ToListAsync();

        var statusText = request.Status switch
        {
            WorkTaskStatus.InProgress => "Đang thực hiện",
            WorkTaskStatus.InReview => "Đang review",
            WorkTaskStatus.Completed => "Hoàn thành",
            WorkTaskStatus.Cancelled => "Đã hủy",
            WorkTaskStatus.OnHold => "Tạm hoãn",
            _ => request.Status.ToString()
        };

        foreach (var task in tasks)
        {
            var oldStatus = task.Status;
            task.Status = request.Status;
            task.UpdatedAt = DateTime.Now;
            task.UpdatedBy = CurrentUserEmail;

            if (request.Status == WorkTaskStatus.InProgress && task.ActualStartDate == null)
                task.ActualStartDate = DateTime.Now;

            if (request.Status == WorkTaskStatus.Completed)
            {
                task.CompletedDate = DateTime.Now;
                task.Progress = 100;
            }

            _dbContext.TaskHistories.Add(CreateHistory(task.Id, "StatusChanged", oldStatus.ToString(), request.Status.ToString()));
        }

        await _dbContext.SaveChangesAsync();

        // Notify assignees about batch status change
        try
        {
            foreach (var task in tasks.Where(t => t.AssigneeId.HasValue))
            {
                var assigneeUserId = await ResolveUserIdFromEmployeeId(task.AssigneeId!.Value);
                if (assigneeUserId.HasValue && assigneeUserId.Value != CurrentUserId)
                {
                    await notificationService.CreateAndSendAsync(
                        assigneeUserId.Value, NotificationType.Info,
                        "Trạng thái công việc thay đổi",
                        $"Công việc \"{task.Title}\" đã chuyển sang: {statusText}",
                        relatedEntityId: task.Id, relatedEntityType: "WorkTask",
                        fromUserId: CurrentUserId, categoryCode: "task", storeId: RequiredStoreId);
                }
                if (request.Status == WorkTaskStatus.Completed && task.AssignedById != Guid.Empty && task.AssignedById != CurrentUserId)
                {
                    await notificationService.CreateAndSendAsync(
                        task.AssignedById, NotificationType.Success,
                        "Công việc hoàn thành",
                        $"Công việc \"{task.Title}\" đã được hoàn thành",
                        relatedEntityId: task.Id, relatedEntityType: "WorkTask",
                        fromUserId: CurrentUserId, categoryCode: "task", storeId: RequiredStoreId);
                }
            }
        }
        catch { /* Notification failure should not affect main operation */ }

        return Ok(AppResponse<int>.Success(tasks.Count));
    }

    /// <summary>
    /// GÃ¡n cÃ´ng viá»‡c hÃ ng loáº¡t
    /// </summary>
    [HttpPost("batch/assign")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<int>>> BatchAssign([FromBody] BatchAssignDto request)
    {
        var tasks = await _dbContext.WorkTasks
            .AsTracking()
            .Where(t => request.TaskIds.Contains(t.Id) && t.StoreId == RequiredStoreId && t.IsActive)
            .ToListAsync();

        foreach (var task in tasks)
        {
            var oldAssignee = task.AssigneeId;
            task.AssigneeId = request.AssigneeId;
            task.UpdatedAt = DateTime.Now;
            task.UpdatedBy = CurrentUserEmail;

            _dbContext.TaskHistories.Add(CreateHistory(task.Id, "AssigneeChanged", oldAssignee?.ToString(), request.AssigneeId.ToString()));
        }

        await _dbContext.SaveChangesAsync();

        // Notify new assignee about batch assignment
        try
        {
            var newAssigneeUserId = await ResolveUserIdFromEmployeeId(request.AssigneeId);
            if (newAssigneeUserId.HasValue && newAssigneeUserId.Value != CurrentUserId)
            {
                foreach (var task in tasks)
                {
                    await notificationService.CreateAndSendAsync(
                        newAssigneeUserId.Value, NotificationType.Info,
                        "Công việc mới được giao",
                        $"Bạn được giao công việc: {task.Title}",
                        relatedEntityId: task.Id, relatedEntityType: "WorkTask",
                        fromUserId: CurrentUserId, categoryCode: "task", storeId: RequiredStoreId);
                }
            }
        }
        catch { /* Notification failure should not affect main operation */ }

        return Ok(AppResponse<int>.Success(tasks.Count));
    }

    /// <summary>
    /// XÃ³a hÃ ng loáº¡t
    /// </summary>
    [HttpPost("batch/delete")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<int>>> BatchDelete([FromBody] BatchDeleteDto request)
    {
        var tasks = await _dbContext.WorkTasks
            .AsTracking()
            .Where(t => request.TaskIds.Contains(t.Id) && t.StoreId == RequiredStoreId)
            .ToListAsync();

        foreach (var task in tasks)
        {
            task.IsActive = false;
            task.Deleted = DateTime.Now;
            task.DeletedBy = CurrentUserEmail;
        }

        await _dbContext.SaveChangesAsync();

        // Notify assignees about batch deletion
        try
        {
            foreach (var task in tasks.Where(t => t.AssigneeId.HasValue))
            {
                var assigneeUserId = await ResolveUserIdFromEmployeeId(task.AssigneeId!.Value);
                if (assigneeUserId.HasValue && assigneeUserId.Value != CurrentUserId)
                {
                    await notificationService.CreateAndSendAsync(
                        assigneeUserId.Value, NotificationType.Warning,
                        "Công việc đã bị xóa",
                        $"Công việc \"{task.Title}\" đã bị xóa",
                        relatedEntityId: task.Id, relatedEntityType: "WorkTask",
                        fromUserId: CurrentUserId, categoryCode: "task", storeId: RequiredStoreId);
                }
            }
        }
        catch { /* Notification failure should not affect main operation */ }

        return Ok(AppResponse<int>.Success(tasks.Count));
    }

    #endregion

    #region Comments

    /// <summary>
    /// Láº¥y comments cá»§a task
    /// </summary>
    [HttpGet("{taskId}/comments")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<List<TaskCommentDto>>>> GetComments(Guid taskId)
    {
        var comments = await _dbContext.TaskComments
            .Include(c => c.User)
            .Include(c => c.Replies!)
                .ThenInclude(r => r.User)
            .Where(c => c.TaskId == taskId && c.ParentCommentId == null)
            .OrderByDescending(c => c.CreatedAt)
            .ToListAsync();

        var dtos = comments.Select(MapCommentToDto).ToList();
        return Ok(AppResponse<List<TaskCommentDto>>.Success(dtos));
    }

    /// <summary>
    /// ThÃªm comment
    /// </summary>
    [HttpPost("{taskId}/comments")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<TaskCommentDto>>> AddComment(Guid taskId, [FromBody] CreateCommentDto request)
    {
        var task = await _dbContext.WorkTasks.FindAsync(taskId);
        if (task == null || task.StoreId != RequiredStoreId)
            return Ok(AppResponse<TaskCommentDto>.Error("Task not found"));

        var comment = new TaskComment
        {
            Id = Guid.NewGuid(),
            TaskId = taskId,
            UserId = CurrentUserId,
            Content = request.Content,
            ParentCommentId = request.ParentCommentId,
            CommentType = request.CommentType,
            ImageUrls = request.ImageUrls,
            LinkUrls = request.LinkUrls,
            ProgressSnapshot = request.ProgressPercent
        };

        _dbContext.TaskComments.Add(comment);

        // If this is a progress update comment, also update task progress
        if (request.CommentType == 1 && request.ProgressPercent.HasValue)
        {
            var oldProgress = task.Progress;
            task.Progress = Math.Clamp(request.ProgressPercent.Value, 0, 100);
            
            if (task.Progress == 100 && task.Status != WorkTaskStatus.Completed)
            {
                task.Status = WorkTaskStatus.Completed;
                task.CompletedDate = DateTime.Now;
            }
            else if (task.Progress > 0 && task.Status == WorkTaskStatus.Todo)
            {
                task.Status = WorkTaskStatus.InProgress;
                task.ActualStartDate ??= DateTime.Now;
            }
            
            task.UpdatedAt = DateTime.Now;
            task.UpdatedBy = CurrentUserEmail;
            
            _dbContext.TaskHistories.Add(CreateHistory(task.Id, "ProgressUpdated", oldProgress.ToString(), task.Progress.ToString()));
        }

        _dbContext.TaskHistories.Add(new TaskHistory
        {
            Id = Guid.NewGuid(),
            TaskId = taskId,
            UserId = CurrentUserId,
            ChangeType = "CommentAdded",
            NewValue = request.Content.Length > 100 ? request.Content[..100] + "..." : request.Content,
            Description = $"Comment added by {CurrentUserEmail}"
        });

        await _dbContext.SaveChangesAsync();

        // Notify task assignees and owner about new comment
        try
        {
            var notifiedUserIds = new HashSet<Guid>();

            // Notify primary assignee
            if (task.AssigneeId.HasValue)
            {
                var assigneeUserId = await ResolveUserIdFromEmployeeId(task.AssigneeId.Value);
                if (assigneeUserId.HasValue && assigneeUserId.Value != CurrentUserId)
                    notifiedUserIds.Add(assigneeUserId.Value);
            }

            // Notify additional assignees
            var taskAssignees = await _dbContext.TaskAssignees
                .Where(ta => ta.TaskId == taskId)
                .Select(ta => ta.EmployeeId)
                .ToListAsync();
            foreach (var empId in taskAssignees)
            {
                var uid = await ResolveUserIdFromEmployeeId(empId);
                if (uid.HasValue && uid.Value != CurrentUserId)
                    notifiedUserIds.Add(uid.Value);
            }

            // Notify task owner if not already notified
            if (task.AssignedById != Guid.Empty && task.AssignedById != CurrentUserId)
                notifiedUserIds.Add(task.AssignedById);

            foreach (var userId in notifiedUserIds)
            {
                await notificationService.CreateAndSendAsync(
                    userId, NotificationType.Info,
                    "Bình luận mới",
                    $"Có bình luận mới trong công việc \"{task.Title}\"",
                    relatedEntityId: task.Id, relatedEntityType: "WorkTask",
                    fromUserId: CurrentUserId, categoryCode: "task", storeId: RequiredStoreId);
            }
        }
        catch { /* Notification failure should not affect main operation */ }

        var createdComment = await _dbContext.TaskComments
            .Include(c => c.User)
            .FirstOrDefaultAsync(c => c.Id == comment.Id);

        return Ok(AppResponse<TaskCommentDto>.Success(MapCommentToDto(createdComment!)));
    }

    /// <summary>
    /// XÃ³a comment
    /// </summary>
    [HttpDelete("{taskId}/comments/{commentId}")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<bool>>> DeleteComment(Guid taskId, Guid commentId)
    {
        var comment = await _dbContext.TaskComments
            .FirstOrDefaultAsync(c => c.Id == commentId && c.TaskId == taskId);

        if (comment == null)
            return Ok(AppResponse<bool>.Error("Comment not found"));

        // Only allow owner or manager to delete
        if (comment.UserId != CurrentUserId && !User.IsInRole("Admin") && !User.IsInRole("Manager"))
            return Ok(AppResponse<bool>.Error("You can only delete your own comments"));

        _dbContext.TaskComments.Remove(comment);
        await _dbContext.SaveChangesAsync();

        return Ok(AppResponse<bool>.Success(true));
    }

    #endregion

    #region Statistics & Kanban

    /// <summary>
    /// Láº¥y thá»‘ng kÃª cÃ´ng viá»‡c
    /// </summary>
    [HttpGet("statistics")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<TaskStatisticsDto>>> GetStatistics(
        [FromQuery] DateTime? fromDate = null,
        [FromQuery] DateTime? toDate = null)
    {
        var query = _dbContext.WorkTasks
            .Where(t => t.StoreId == RequiredStoreId && t.IsActive);

        if (fromDate.HasValue)
            query = query.Where(t => t.CreatedAt >= fromDate.Value);
        if (toDate.HasValue)
            query = query.Where(t => t.CreatedAt <= toDate.Value);

        // Use server-side aggregation instead of loading all tasks into memory
        var now = DateTime.Now;
        var statusCounts = await query
            .GroupBy(t => t.Status)
            .Select(g => new { Status = g.Key, Count = g.Count() })
            .ToListAsync();
        var totalTasks = statusCounts.Sum(x => x.Count);
        var completedCount = statusCounts.FirstOrDefault(x => x.Status == WorkTaskStatus.Completed)?.Count ?? 0;

        var overdueCount = await query
            .CountAsync(t => t.DueDate < now && t.Status != WorkTaskStatus.Completed && t.Status != WorkTaskStatus.Cancelled);
        var avgProgress = totalTasks > 0 ? await query.AverageAsync(t => t.Progress) : 0;

        var byPriority = await query
            .GroupBy(t => t.Priority)
            .Select(g => new TasksByPriorityDto { Priority = g.Key, Count = g.Count() })
            .OrderByDescending(x => x.Priority)
            .ToListAsync();

        var byType = await query
            .GroupBy(t => t.TaskType)
            .Select(g => new TasksByTypeDto { TaskType = g.Key, Count = g.Count() })
            .ToListAsync();

        var stats = new TaskStatisticsDto
        {
            TotalTasks = totalTasks,
            TodoCount = statusCounts.FirstOrDefault(x => x.Status == WorkTaskStatus.Todo)?.Count ?? 0,
            InProgressCount = statusCounts.FirstOrDefault(x => x.Status == WorkTaskStatus.InProgress)?.Count ?? 0,
            InReviewCount = statusCounts.FirstOrDefault(x => x.Status == WorkTaskStatus.InReview)?.Count ?? 0,
            CompletedCount = completedCount,
            CancelledCount = statusCounts.FirstOrDefault(x => x.Status == WorkTaskStatus.Cancelled)?.Count ?? 0,
            OnHoldCount = statusCounts.FirstOrDefault(x => x.Status == WorkTaskStatus.OnHold)?.Count ?? 0,
            OverdueCount = overdueCount,
            CompletionRate = totalTasks > 0 ? Math.Round((double)completedCount / totalTasks * 100, 1) : 0,
            AverageProgress = Math.Round(avgProgress, 1),
            ByPriority = byPriority,
            ByType = byType
        };

        // By Assignee - server-side aggregation
        var assigneeQuery = _dbContext.WorkTasks
            .Where(t => t.StoreId == RequiredStoreId && t.IsActive && t.AssigneeId != null);

        stats.ByAssignee = await assigneeQuery
            .GroupBy(t => new { t.AssigneeId, t.Assignee!.FirstName, t.Assignee!.LastName })
            .Select(g => new TasksByAssigneeDto
            {
                EmployeeId = g.Key.AssigneeId!.Value,
                EmployeeName = (g.Key.LastName ?? "") + " " + (g.Key.FirstName ?? ""),
                TotalTasks = g.Count(),
                CompletedTasks = g.Count(t => t.Status == WorkTaskStatus.Completed),
                InProgressTasks = g.Count(t => t.Status == WorkTaskStatus.InProgress),
                OverdueTasks = g.Count(t => t.DueDate < now && t.Status != WorkTaskStatus.Completed && t.Status != WorkTaskStatus.Cancelled)
            })
            .OrderByDescending(x => x.TotalTasks)
            .Take(10)
            .ToListAsync();

        return Ok(AppResponse<TaskStatisticsDto>.Success(stats));
    }

    /// <summary>
    /// Láº¥y Kanban board view
    /// </summary>
    [HttpGet("kanban")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<KanbanBoardDto>>> GetKanbanBoard(
        [FromQuery] Guid? assigneeId = null,
        [FromQuery] TaskPriority? priority = null)
    {
        var query = _dbContext.WorkTasks
            .Include(t => t.Assignee)
            .Include(t => t.AssignedBy)
            .Include(t => t.TaskAssignees!)
                .ThenInclude(ta => ta.Employee)
            .Where(t => t.StoreId == RequiredStoreId && t.IsActive && t.ParentTaskId == null);

        if (assigneeId.HasValue)
            query = query.Where(t => t.AssigneeId == assigneeId.Value || t.TaskAssignees!.Any(ta => ta.EmployeeId == assigneeId.Value));

        if (priority.HasValue)
            query = query.Where(t => t.Priority == priority.Value);

        var tasks = await query.OrderByDescending(t => t.Priority).ThenBy(t => t.DueDate).ToListAsync();

        var statuses = new[] { WorkTaskStatus.Todo, WorkTaskStatus.InProgress, WorkTaskStatus.InReview, WorkTaskStatus.Completed };

        var board = new KanbanBoardDto
        {
            Columns = statuses.Select(status => new KanbanColumnDto
            {
                Status = status,
                TaskCount = tasks.Count(t => t.Status == status),
                Tasks = tasks.Where(t => t.Status == status).Select(t => MapToDto(t)).ToList()
            }).ToList()
        };

        return Ok(AppResponse<KanbanBoardDto>.Success(board));
    }

    /// <summary>
    /// Láº¥y lá»‹ch sá»­ task
    /// </summary>
    [HttpGet("{taskId}/history")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<List<TaskHistoryDto>>>> GetTaskHistory(Guid taskId)
    {
        var histories = await _dbContext.TaskHistories
            .Include(h => h.User)
            .Where(h => h.TaskId == taskId)
            .OrderByDescending(h => h.CreatedAt)
            .Take(50)
            .ToListAsync();

        var dtos = histories.Select(h => new TaskHistoryDto
        {
            Id = h.Id,
            TaskId = h.TaskId,
            UserId = h.UserId,
            UserName = h.User?.UserName,
            ChangeType = h.ChangeType,
            OldValue = h.OldValue,
            NewValue = h.NewValue,
            Description = h.Description,
            CreatedAt = h.CreatedAt
        }).ToList();

        return Ok(AppResponse<List<TaskHistoryDto>>.Success(dtos));
    }

    #endregion

    #region Reminders (Đốc thúc)

    /// <summary>
    /// Gửi đốc thúc công việc
    /// </summary>
    [HttpPost("{taskId}/reminders")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<TaskReminderDto>>> SendReminder(Guid taskId, [FromBody] CreateReminderDto request)
    {
        var task = await _dbContext.WorkTasks
            .Include(t => t.Assignee)
            .FirstOrDefaultAsync(t => t.Id == taskId && t.StoreId == RequiredStoreId);

        if (task == null)
            return Ok(AppResponse<TaskReminderDto>.Error("Task not found"));

        var reminder = new TaskReminder
        {
            Id = Guid.NewGuid(),
            TaskId = taskId,
            SentById = CurrentUserId,
            SentToId = request.SentToId,
            Message = request.Message,
            UrgencyLevel = request.UrgencyLevel
        };

        _dbContext.TaskReminders.Add(reminder);

        _dbContext.TaskHistories.Add(new TaskHistory
        {
            Id = Guid.NewGuid(),
            TaskId = taskId,
            UserId = CurrentUserId,
            ChangeType = "ReminderSent",
            NewValue = request.Message.Length > 100 ? request.Message[..100] + "..." : request.Message,
            Description = $"Đốc thúc gửi bởi {CurrentUserEmail}"
        });

        await _dbContext.SaveChangesAsync();

        // Notify reminder target - resolve Employee.Id → ApplicationUser.Id
        try
        {
            var sentToUserId = await ResolveUserIdFromEmployeeId(request.SentToId);
            if (sentToUserId.HasValue)
            {
                await notificationService.CreateAndSendAsync(
                    sentToUserId.Value, NotificationType.Reminder,
                    "Đốc thúc công việc",
                    $"Bạn được nhắc về công việc \"{task.Title}\": {(request.Message.Length > 100 ? request.Message[..100] + "..." : request.Message)}",
                    relatedEntityId: task.Id, relatedEntityType: "WorkTask",
                    fromUserId: CurrentUserId, categoryCode: "task", storeId: RequiredStoreId);
            }
        }
        catch { /* Notification failure should not affect main operation */ }

        var dto = await _dbContext.TaskReminders
            .Include(r => r.SentBy)
            .Include(r => r.SentTo)
            .Include(r => r.Task)
            .Where(r => r.Id == reminder.Id)
            .Select(r => new TaskReminderDto
            {
                Id = r.Id,
                TaskId = r.TaskId,
                TaskTitle = r.Task!.Title,
                TaskCode = r.Task.TaskCode,
                SentById = r.SentById,
                SentByName = r.SentBy!.UserName,
                SentToId = r.SentToId,
                SentToName = r.SentTo != null ? r.SentTo.LastName + " " + r.SentTo.FirstName : null,
                Message = r.Message,
                UrgencyLevel = r.UrgencyLevel,
                IsRead = r.IsRead,
                ReadAt = r.ReadAt,
                CreatedAt = r.CreatedAt
            })
            .FirstAsync();

        return Ok(AppResponse<TaskReminderDto>.Success(dto));
    }

    /// <summary>
    /// Lấy danh sách đốc thúc của task
    /// </summary>
    [HttpGet("{taskId}/reminders")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<List<TaskReminderDto>>>> GetReminders(Guid taskId)
    {
        var reminders = await _dbContext.TaskReminders
            .Include(r => r.SentBy)
            .Include(r => r.SentTo)
            .Where(r => r.TaskId == taskId)
            .OrderByDescending(r => r.CreatedAt)
            .Select(r => new TaskReminderDto
            {
                Id = r.Id,
                TaskId = r.TaskId,
                SentById = r.SentById,
                SentByName = r.SentBy!.UserName,
                SentToId = r.SentToId,
                SentToName = r.SentTo != null ? r.SentTo.LastName + " " + r.SentTo.FirstName : null,
                Message = r.Message,
                UrgencyLevel = r.UrgencyLevel,
                IsRead = r.IsRead,
                ReadAt = r.ReadAt,
                CreatedAt = r.CreatedAt
            })
            .ToListAsync();

        return Ok(AppResponse<List<TaskReminderDto>>.Success(reminders));
    }

    /// <summary>
    /// Đánh dấu đốc thúc đã đọc
    /// </summary>
    [HttpPatch("reminders/{reminderId}/read")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<bool>>> MarkReminderRead(Guid reminderId)
    {
        var reminder = await _dbContext.TaskReminders.FindAsync(reminderId);
        if (reminder == null)
            return Ok(AppResponse<bool>.Error("Reminder not found"));

        reminder.IsRead = true;
        reminder.ReadAt = DateTime.Now;
        await _dbContext.SaveChangesAsync();

        return Ok(AppResponse<bool>.Success(true));
    }

    #endregion

    #region Evaluations (Đánh giá)

    /// <summary>
    /// Đánh giá công việc
    /// </summary>
    [HttpPost("{taskId}/evaluations")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<TaskEvaluationDto>>> CreateEvaluation(Guid taskId, [FromBody] CreateEvaluationDto request)
    {
        var task = await _dbContext.WorkTasks
            .FirstOrDefaultAsync(t => t.Id == taskId && t.StoreId == RequiredStoreId);

        if (task == null)
            return Ok(AppResponse<TaskEvaluationDto>.Error("Task not found"));

        // Check if already evaluated by this user
        var existing = await _dbContext.TaskEvaluations
            .AsTracking()
            .FirstOrDefaultAsync(e => e.TaskId == taskId && e.EvaluatorId == CurrentUserId);

        if (existing != null)
        {
            existing.QualityScore = request.QualityScore;
            existing.TimelinessScore = request.TimelinessScore;
            existing.OverallScore = request.OverallScore;
            existing.Comment = request.Comment;
            existing.UpdatedAt = DateTime.Now;
        }
        else
        {
            existing = new TaskEvaluation
            {
                Id = Guid.NewGuid(),
                TaskId = taskId,
                EvaluatorId = CurrentUserId,
                QualityScore = request.QualityScore,
                TimelinessScore = request.TimelinessScore,
                OverallScore = request.OverallScore,
                Comment = request.Comment
            };
            _dbContext.TaskEvaluations.Add(existing);
        }

        _dbContext.TaskHistories.Add(new TaskHistory
        {
            Id = Guid.NewGuid(),
            TaskId = taskId,
            UserId = CurrentUserId,
            ChangeType = "Evaluated",
            NewValue = $"Chất lượng: {request.QualityScore}/5, Tiến độ: {request.TimelinessScore}/5, Tổng: {request.OverallScore}/5",
            Description = $"Đánh giá bởi {CurrentUserEmail}"
        });

        await _dbContext.SaveChangesAsync();

        // Notify task assignee about evaluation - resolve Employee.Id → ApplicationUser.Id
        try
        {
            if (task.AssigneeId.HasValue)
            {
                var assigneeUserId = await ResolveUserIdFromEmployeeId(task.AssigneeId.Value);
                if (assigneeUserId.HasValue && assigneeUserId.Value != CurrentUserId)
                {
                    await notificationService.CreateAndSendAsync(
                        assigneeUserId.Value, NotificationType.Info,
                        "Đánh giá công việc",
                        $"Công việc \"{task.Title}\" đã được đánh giá: {request.OverallScore}/5",
                        relatedEntityId: task.Id, relatedEntityType: "WorkTask",
                        fromUserId: CurrentUserId, categoryCode: "task", storeId: RequiredStoreId);
                }
            }
        }
        catch { /* Notification failure should not affect main operation */ }

        return Ok(AppResponse<TaskEvaluationDto>.Success(new TaskEvaluationDto
        {
            Id = existing.Id,
            TaskId = taskId,
            TaskTitle = task.Title,
            EvaluatorId = existing.EvaluatorId,
            QualityScore = existing.QualityScore,
            TimelinessScore = existing.TimelinessScore,
            OverallScore = existing.OverallScore,
            Comment = existing.Comment,
            CreatedAt = existing.CreatedAt
        }));
    }

    /// <summary>
    /// Lấy đánh giá của task
    /// </summary>
    [HttpGet("{taskId}/evaluations")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<List<TaskEvaluationDto>>>> GetEvaluations(Guid taskId)
    {
        var evaluations = await _dbContext.TaskEvaluations
            .Include(e => e.Evaluator)
            .Include(e => e.Task)
            .Where(e => e.TaskId == taskId)
            .OrderByDescending(e => e.CreatedAt)
            .Select(e => new TaskEvaluationDto
            {
                Id = e.Id,
                TaskId = e.TaskId,
                TaskTitle = e.Task!.Title,
                EvaluatorId = e.EvaluatorId,
                EvaluatorName = e.Evaluator!.UserName,
                QualityScore = e.QualityScore,
                TimelinessScore = e.TimelinessScore,
                OverallScore = e.OverallScore,
                Comment = e.Comment,
                CreatedAt = e.CreatedAt
            })
            .ToListAsync();

        return Ok(AppResponse<List<TaskEvaluationDto>>.Success(evaluations));
    }

    #endregion

    #region Update Task (full update)

    /// <summary>
    /// Cập nhật công việc (dùng trong Flutter)
    /// </summary>
    [HttpPut("{id}/full")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<WorkTaskDto>>> UpdateTaskFull(Guid id, [FromBody] UpdateTaskDto request)
    {
        var task = await _dbContext.WorkTasks
            .AsTracking()
            .FirstOrDefaultAsync(t => t.Id == id && t.StoreId == RequiredStoreId);

        if (task == null)
            return Ok(AppResponse<WorkTaskDto>.Error("Task not found"));

        var histories = new List<TaskHistory>();

        if (request.Title != null && request.Title != task.Title)
        {
            histories.Add(CreateHistory(task.Id, "TitleChanged", task.Title, request.Title));
            task.Title = request.Title;
        }
        if (request.Description != null) task.Description = request.Description;
        if (request.TaskType.HasValue && request.TaskType.Value != task.TaskType)
        {
            histories.Add(CreateHistory(task.Id, "TypeChanged", task.TaskType.ToString(), request.TaskType.Value.ToString()));
            task.TaskType = request.TaskType.Value;
        }
        if (request.Priority.HasValue && request.Priority.Value != task.Priority)
        {
            histories.Add(CreateHistory(task.Id, "PriorityChanged", task.Priority.ToString(), request.Priority.Value.ToString()));
            task.Priority = request.Priority.Value;
        }
        if (request.Status.HasValue && request.Status.Value != task.Status)
        {
            histories.Add(CreateHistory(task.Id, "StatusChanged", task.Status.ToString(), request.Status.Value.ToString()));
            task.Status = request.Status.Value;
            if (request.Status.Value == WorkTaskStatus.InProgress && task.ActualStartDate == null) task.ActualStartDate = DateTime.Now;
            if (request.Status.Value == WorkTaskStatus.Completed) { task.CompletedDate = DateTime.Now; task.Progress = 100; }
        }
        if (request.Progress.HasValue && request.Progress.Value != task.Progress)
        {
            histories.Add(CreateHistory(task.Id, "ProgressUpdated", task.Progress.ToString(), request.Progress.Value.ToString()));
            task.Progress = request.Progress.Value;
        }
        Guid? oldFullAssigneeId = null;
        if (request.AssigneeId.HasValue && request.AssigneeId != task.AssigneeId)
        {
            oldFullAssigneeId = task.AssigneeId;
            histories.Add(CreateHistory(task.Id, "AssigneeChanged", task.AssigneeId?.ToString(), request.AssigneeId.Value.ToString()));
            task.AssigneeId = request.AssigneeId;
        }

        task.StartDate = request.StartDate ?? task.StartDate;
        task.DueDate = request.DueDate ?? task.DueDate;
        task.EstimatedHours = request.EstimatedHours ?? task.EstimatedHours;
        task.ActualHours = request.ActualHours ?? task.ActualHours;
        task.Tags = request.Tags ?? task.Tags;
        task.Checklist = request.Checklist ?? task.Checklist;
        task.CompletionNotes = request.CompletionNotes ?? task.CompletionNotes;

        task.UpdatedAt = DateTime.Now;
        task.UpdatedBy = CurrentUserEmail;

        if (histories.Any()) _dbContext.TaskHistories.AddRange(histories);
        await _dbContext.SaveChangesAsync();

        // Notify new assignee when task is reassigned
        try
        {
            if (oldFullAssigneeId.HasValue && task.AssigneeId.HasValue)
            {
                var newAssigneeUserId = await ResolveUserIdFromEmployeeId(task.AssigneeId.Value);
                if (newAssigneeUserId.HasValue && newAssigneeUserId.Value != CurrentUserId)
                {
                    await notificationService.CreateAndSendAsync(
                        newAssigneeUserId.Value, NotificationType.Info,
                        "Công việc mới được giao",
                        $"Bạn được giao công việc: {task.Title}",
                        relatedEntityId: task.Id, relatedEntityType: "WorkTask",
                        fromUserId: CurrentUserId, categoryCode: "task", storeId: RequiredStoreId);
                }
            }
        }
        catch { /* Notification failure should not affect main operation */ }

        var updatedTask = await _dbContext.WorkTasks.Include(t => t.Assignee).Include(t => t.AssignedBy).FirstOrDefaultAsync(t => t.Id == task.Id);
        return Ok(AppResponse<WorkTaskDto>.Success(MapToDto(updatedTask!)));
    }

    #endregion

    #region Private Helpers

    private WorkTaskDto MapToDto(WorkTask task, bool includeDetails = false)
    {
        var dto = new WorkTaskDto
        {
            Id = task.Id,
            TaskCode = task.TaskCode,
            Title = task.Title,
            Description = task.Description,
            TaskType = task.TaskType,
            Priority = task.Priority,
            Status = task.Status,
            Progress = task.Progress,
            StoreId = task.StoreId,
            StoreName = task.Store?.Name,
            AssignedById = task.AssignedById,
            AssignedByName = task.AssignedBy?.UserName,
            AssigneeId = task.AssigneeId,
            AssigneeName = task.Assignee != null ? $"{task.Assignee.LastName} {task.Assignee.FirstName}" : null,
            StartDate = task.StartDate,
            DueDate = task.DueDate,
            ActualStartDate = task.ActualStartDate,
            CompletedDate = task.CompletedDate,
            EstimatedHours = task.EstimatedHours,
            ActualHours = task.ActualHours,
            ParentTaskId = task.ParentTaskId,
            ParentTaskTitle = task.ParentTask?.Title,
            Tags = task.Tags,
            Checklist = task.Checklist,
            CompletionNotes = task.CompletionNotes,
            CreatedAt = task.CreatedAt,
            CreatedBy = task.CreatedBy,
            UpdatedAt = task.UpdatedAt,
            IsActive = task.IsActive,
            Assignees = task.TaskAssignees?.Select(ta => new TaskAssigneeDto
            {
                Id = ta.Id,
                TaskId = ta.TaskId,
                EmployeeId = ta.EmployeeId,
                EmployeeName = ta.Employee != null ? $"{ta.Employee.LastName} {ta.Employee.FirstName}" : null,
                EmployeeCode = ta.Employee?.EmployeeCode,
                Role = ta.Role,
                AssignedAt = ta.AssignedAt
            }).ToList()
        };

        if (includeDetails)
        {
            dto.Comments = task.Comments?.Where(c => c.ParentCommentId == null)
                .Select(MapCommentToDto).ToList();
            dto.Attachments = task.Attachments?.Select(a => new TaskAttachmentDto
            {
                Id = a.Id,
                TaskId = a.TaskId,
                UploadedById = a.UploadedById,
                UploadedByName = a.UploadedBy?.UserName,
                FileName = a.FileName,
                FilePath = a.FilePath,
                ContentType = a.ContentType,
                FileSize = a.FileSize,
                CreatedAt = a.CreatedAt
            }).ToList();
            dto.SubTasks = task.SubTasks?.Select(st => MapToDto(st)).ToList();
        }

        return dto;
    }

    private TaskCommentDto MapCommentToDto(TaskComment comment)
    {
        return new TaskCommentDto
        {
            Id = comment.Id,
            TaskId = comment.TaskId,
            UserId = comment.UserId,
            UserName = comment.User?.UserName,
            Content = comment.Content,
            ParentCommentId = comment.ParentCommentId,
            CommentType = comment.CommentType,
            ImageUrls = comment.ImageUrls,
            LinkUrls = comment.LinkUrls,
            ProgressSnapshot = comment.ProgressSnapshot,
            CreatedAt = comment.CreatedAt,
            Replies = comment.Replies?.Select(MapCommentToDto).ToList()
        };
    }

    private TaskHistory CreateHistory(Guid taskId, string changeType, string? oldValue, string? newValue)
    {
        return new TaskHistory
        {
            Id = Guid.NewGuid(),
            TaskId = taskId,
            UserId = CurrentUserId,
            ChangeType = changeType,
            OldValue = oldValue,
            NewValue = newValue,
            Description = $"{changeType}: {oldValue ?? "null"} â†’ {newValue}"
        };
    }

    #endregion
}



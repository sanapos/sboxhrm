using System.Text;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.DTOs.Tasks;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure.Services;

namespace ZKTecoADMS.Api.Controllers;

public partial class TasksController
{
    [HttpGet("assignment-dashboard")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("Task", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<TaskAssignmentDashboardDto>>> GetAssignmentDashboard(
        [FromQuery] Guid? branchId = null)
    {
        var storeId = RequiredStoreId;
        var now = DateTime.Now;
        var query = _dbContext.WorkTasks.Where(t => t.StoreId == storeId && t.IsActive);

        if (branchId.HasValue)
        {
            var branchScope = await BranchQueryHelper.ResolveEmployeeScopeAsync(
                _dbContext, storeId, branchId, true);
            query = TaskWorkflowHelper.ApplyBranchFilter(query, branchScope);
        }

        var isManager = TaskWorkflowHelper.IsManagerOrAdmin(User);
        IQueryable<WorkTask> myAssignedQuery = query.Where(t => t.AssignedById == CurrentUserId);
        if (!isManager)
            myAssignedQuery = myAssignedQuery.Where(t => false);

        var employee = await TaskWorkflowHelper.GetEmployeeForUserAsync(
            _dbContext, storeId, CurrentUserId);

        var pendingAcceptance = employee == null
            ? new List<WorkTask>()
            : await query
                .Where(t => t.Status == WorkTaskStatus.Assigned &&
                    (t.AssigneeId == employee.Id ||
                     t.TaskAssignees!.Any(ta => ta.EmployeeId == employee.Id)))
                .OrderByDescending(t => t.CreatedAt)
                .Take(20)
                .Include(t => t.Assignee)
                .Include(t => t.AssignedBy)
                .Include(t => t.TaskAssignees!)
                    .ThenInclude(ta => ta.Employee)
                .ToListAsync();

        var recentlyAssigned = await myAssignedQuery
            .OrderByDescending(t => t.UpdatedAt ?? t.CreatedAt)
            .Take(15)
            .Include(t => t.Assignee)
            .Include(t => t.AssignedBy)
            .Include(t => t.TaskAssignees!)
                .ThenInclude(ta => ta.Employee)
            .ToListAsync();

        var dashboard = new TaskAssignmentDashboardDto
        {
            AssignedByMeCount = isManager
                ? await myAssignedQuery.CountAsync()
                : 0,
            PendingAcceptanceCount = pendingAcceptance.Count,
            OverdueAssignedCount = isManager
                ? await myAssignedQuery.CountAsync(t =>
                    t.DueDate < now &&
                    t.Status != WorkTaskStatus.Completed &&
                    t.Status != WorkTaskStatus.Cancelled)
                : 0,
            MyActiveCount = employee == null
                ? 0
                : await query.CountAsync(t =>
                    (t.AssigneeId == employee.Id ||
                     t.TaskAssignees!.Any(ta => ta.EmployeeId == employee.Id)) &&
                    t.Status != WorkTaskStatus.Completed &&
                    t.Status != WorkTaskStatus.Cancelled),
            PendingAcceptance = pendingAcceptance.Select(t => MapToDto(t)).ToList(),
            RecentlyAssigned = recentlyAssigned.Select(t => MapToDto(t)).ToList()
        };

        if (isManager)
        {
            dashboard.WorkloadByAssignee = await myAssignedQuery
                .Where(t => t.AssigneeId != null)
                .GroupBy(t => new { t.AssigneeId, t.Assignee!.FirstName, t.Assignee!.LastName })
                .Select(g => new TasksByAssigneeDto
                {
                    EmployeeId = g.Key.AssigneeId!.Value,
                    EmployeeName = (g.Key.LastName ?? "") + " " + (g.Key.FirstName ?? ""),
                    TotalTasks = g.Count(),
                    CompletedTasks = g.Count(t => t.Status == WorkTaskStatus.Completed),
                    InProgressTasks = g.Count(t => t.Status == WorkTaskStatus.InProgress),
                    OverdueTasks = g.Count(t =>
                        t.DueDate < now &&
                        t.Status != WorkTaskStatus.Completed &&
                        t.Status != WorkTaskStatus.Cancelled)
                })
                .OrderByDescending(x => x.TotalTasks)
                .Take(12)
                .ToListAsync();
        }

        return Ok(AppResponse<TaskAssignmentDashboardDto>.Success(dashboard));
    }

    [HttpPatch("{id}/accept")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("Task", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<WorkTaskDto>>> AcceptTask(
        Guid id, [FromBody] AcceptTaskDto? request)
    {
        var task = await _dbContext.WorkTasks
            .AsTracking()
            .FirstOrDefaultAsync(t => t.Id == id && t.StoreId == RequiredStoreId && t.IsActive);

        if (task == null)
            return Ok(AppResponse<WorkTaskDto>.Error("Task not found"));

        if (task.Status != WorkTaskStatus.Assigned)
            return Ok(AppResponse<WorkTaskDto>.Error("Công việc không ở trạng thái chờ xác nhận"));

        var employee = await TaskWorkflowHelper.GetEmployeeForUserAsync(
            _dbContext, RequiredStoreId, CurrentUserId);
        if (employee == null ||
            !await TaskWorkflowHelper.IsTaskParticipantAsync(_dbContext, task, employee.Id))
            return Ok(AppResponse<WorkTaskDto>.Error("Bạn không phải người được giao việc này"));

        task.AcceptedAt = DateTime.Now;
        task.RejectionReason = null;
        task.Status = request?.StartImmediately == true
            ? WorkTaskStatus.InProgress
            : WorkTaskStatus.Todo;
        if (task.Status == WorkTaskStatus.InProgress)
            task.ActualStartDate ??= DateTime.Now;

        task.UpdatedAt = DateTime.Now;
        task.UpdatedBy = CurrentUserEmail;

        _dbContext.TaskHistories.Add(CreateHistory(
            task.Id, "AssignmentAccepted", WorkTaskStatus.Assigned.ToString(), task.Status.ToString()));

        await _dbContext.SaveChangesAsync();

        try
        {
            if (task.AssignedById != CurrentUserId)
            {
                await notificationService.CreateAndSendAsync(
                    task.AssignedById, NotificationType.Success,
                    "Đã nhận việc",
                    $"\"{task.Title}\" đã được xác nhận nhận việc",
                    relatedEntityId: task.Id, relatedEntityType: "WorkTask",
                    fromUserId: CurrentUserId, categoryCode: "task", storeId: RequiredStoreId);
            }
        }
        catch { }

        var updated = await _dbContext.WorkTasks
            .Include(t => t.Assignee).Include(t => t.AssignedBy)
            .FirstAsync(t => t.Id == id);
        return Ok(AppResponse<WorkTaskDto>.Success(MapToDto(updated)));
    }

    [HttpPatch("{id}/reject")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("Task", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<WorkTaskDto>>> RejectTask(
        Guid id, [FromBody] RejectTaskDto request)
    {
        var task = await _dbContext.WorkTasks
            .AsTracking()
            .FirstOrDefaultAsync(t => t.Id == id && t.StoreId == RequiredStoreId && t.IsActive);

        if (task == null)
            return Ok(AppResponse<WorkTaskDto>.Error("Task not found"));

        if (task.Status != WorkTaskStatus.Assigned)
            return Ok(AppResponse<WorkTaskDto>.Error("Công việc không ở trạng thái chờ xác nhận"));

        var employee = await TaskWorkflowHelper.GetEmployeeForUserAsync(
            _dbContext, RequiredStoreId, CurrentUserId);
        if (employee == null ||
            !await TaskWorkflowHelper.IsTaskParticipantAsync(_dbContext, task, employee.Id))
            return Ok(AppResponse<WorkTaskDto>.Error("Bạn không phải người được giao việc này"));

        task.Status = WorkTaskStatus.Cancelled;
        task.RejectionReason = string.IsNullOrWhiteSpace(request.Reason)
            ? "Từ chối nhận việc"
            : request.Reason.Trim();
        task.UpdatedAt = DateTime.Now;
        task.UpdatedBy = CurrentUserEmail;

        _dbContext.TaskHistories.Add(CreateHistory(
            task.Id, "AssignmentRejected", WorkTaskStatus.Assigned.ToString(), task.RejectionReason));

        await _dbContext.SaveChangesAsync();

        try
        {
            if (task.AssignedById != CurrentUserId)
            {
                await notificationService.CreateAndSendAsync(
                    task.AssignedById, NotificationType.Warning,
                    "Từ chối nhận việc",
                    $"\"{task.Title}\" bị từ chối: {task.RejectionReason}",
                    relatedEntityId: task.Id, relatedEntityType: "WorkTask",
                    fromUserId: CurrentUserId, categoryCode: "task", storeId: RequiredStoreId);
            }
        }
        catch { }

        var updated = await _dbContext.WorkTasks
            .Include(t => t.Assignee).Include(t => t.AssignedBy)
            .FirstAsync(t => t.Id == id);
        return Ok(AppResponse<WorkTaskDto>.Success(MapToDto(updated)));
    }

    [HttpGet("templates")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("Task", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<TaskTemplateDto>>>> GetTemplates()
    {
        var list = await _dbContext.TaskTemplates
            .Where(t => t.StoreId == RequiredStoreId && t.IsActive)
            .OrderBy(t => t.Name)
            .Select(t => new TaskTemplateDto
            {
                Id = t.Id,
                Name = t.Name,
                Title = t.Title,
                Description = t.Description,
                TaskType = t.TaskType,
                Priority = t.Priority,
                EstimatedHours = t.EstimatedHours,
                DefaultSlaReminderHours = t.DefaultSlaReminderHours,
                Tags = t.Tags,
                Checklist = t.Checklist,
                IsActive = t.IsActive
            })
            .ToListAsync();
        return Ok(AppResponse<List<TaskTemplateDto>>.Success(list));
    }

    [HttpPost("templates")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("Task", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<TaskTemplateDto>>> CreateTemplate(
        [FromBody] CreateTaskTemplateDto request)
    {
        var entity = new TaskTemplate
        {
            Id = Guid.NewGuid(),
            StoreId = RequiredStoreId,
            Name = request.Name,
            Title = request.Title,
            Description = request.Description,
            TaskType = request.TaskType,
            Priority = request.Priority,
            EstimatedHours = request.EstimatedHours,
            DefaultSlaReminderHours = request.DefaultSlaReminderHours,
            Tags = request.Tags,
            Checklist = request.Checklist,
            IsActive = true,
            CreatedBy = CurrentUserEmail
        };
        _dbContext.TaskTemplates.Add(entity);
        await _dbContext.SaveChangesAsync();

        return Ok(AppResponse<TaskTemplateDto>.Success(new TaskTemplateDto
        {
            Id = entity.Id,
            Name = entity.Name,
            Title = entity.Title,
            Description = entity.Description,
            TaskType = entity.TaskType,
            Priority = entity.Priority,
            EstimatedHours = entity.EstimatedHours,
            DefaultSlaReminderHours = entity.DefaultSlaReminderHours,
            Tags = entity.Tags,
            Checklist = entity.Checklist,
            IsActive = entity.IsActive
        }));
    }

    [HttpPost("from-template")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("Task", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<WorkTaskDto>>> CreateFromTemplate(
        [FromBody] CreateTaskFromTemplateDto request)
    {
        var template = await _dbContext.TaskTemplates
            .FirstOrDefaultAsync(t =>
                t.Id == request.TemplateId &&
                t.StoreId == RequiredStoreId &&
                t.IsActive);
        if (template == null)
            return Ok(AppResponse<WorkTaskDto>.Error("Template not found"));

        return await CreateTask(new CreateTaskDto
        {
            Title = template.Title,
            Description = template.Description,
            TaskType = template.TaskType,
            Priority = template.Priority,
            AssigneeId = request.AssigneeId,
            AssigneeIds = request.AssigneeIds,
            StartDate = request.StartDate,
            DueDate = request.DueDate,
            EstimatedHours = template.EstimatedHours,
            Tags = template.Tags,
            Checklist = template.Checklist,
            BranchId = request.BranchId,
            DepartmentId = request.DepartmentId,
            TemplateId = template.Id,
            SlaReminderHours = template.DefaultSlaReminderHours ?? 24,
            RequireAcceptance = true
        });
    }

    [HttpGet("{taskId}/dependencies")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("Task", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<TaskDependencyDto>>>> GetDependencies(Guid taskId)
    {
        var list = await _dbContext.TaskDependencies
            .Include(d => d.DependsOnTask)
            .Where(d => d.TaskId == taskId)
            .Select(d => new TaskDependencyDto
            {
                Id = d.Id,
                TaskId = d.TaskId,
                DependsOnTaskId = d.DependsOnTaskId,
                DependsOnTaskTitle = d.DependsOnTask!.Title,
                DependsOnStatus = d.DependsOnTask.Status
            })
            .ToListAsync();
        return Ok(AppResponse<List<TaskDependencyDto>>.Success(list));
    }

    [HttpPost("{taskId}/dependencies")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("Task", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<TaskDependencyDto>>> AddDependency(
        Guid taskId, [FromBody] AddTaskDependencyDto request)
    {
        if (taskId == request.DependsOnTaskId)
            return Ok(AppResponse<TaskDependencyDto>.Error("Không thể phụ thuộc chính nó"));

        var exists = await _dbContext.TaskDependencies.AnyAsync(d =>
            d.TaskId == taskId && d.DependsOnTaskId == request.DependsOnTaskId);
        if (exists)
            return Ok(AppResponse<TaskDependencyDto>.Error("Phụ thuộc đã tồn tại"));

        var dep = new TaskDependency
        {
            Id = Guid.NewGuid(),
            TaskId = taskId,
            DependsOnTaskId = request.DependsOnTaskId
        };
        _dbContext.TaskDependencies.Add(dep);
        await _dbContext.SaveChangesAsync();

        var blocker = await _dbContext.WorkTasks.FindAsync(request.DependsOnTaskId);
        return Ok(AppResponse<TaskDependencyDto>.Success(new TaskDependencyDto
        {
            Id = dep.Id,
            TaskId = taskId,
            DependsOnTaskId = request.DependsOnTaskId,
            DependsOnTaskTitle = blocker?.Title,
            DependsOnStatus = blocker?.Status
        }));
    }

    [HttpDelete("{taskId}/dependencies/{dependencyId}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("Task", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<bool>>> RemoveDependency(
        Guid taskId, Guid dependencyId)
    {
        var dep = await _dbContext.TaskDependencies
            .FirstOrDefaultAsync(d => d.Id == dependencyId && d.TaskId == taskId);
        if (dep == null)
            return Ok(AppResponse<bool>.Error("Dependency not found"));
        _dbContext.TaskDependencies.Remove(dep);
        await _dbContext.SaveChangesAsync();
        return Ok(AppResponse<bool>.Success(true));
    }

    [HttpGet("export")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("Task", ModulePermissionAction.View)]
    public async Task<IActionResult> ExportTasks(
        [FromQuery] DateTime? fromDate = null,
        [FromQuery] DateTime? toDate = null,
        [FromQuery] Guid? branchId = null)
    {
        var query = _dbContext.WorkTasks
            .Include(t => t.Assignee)
            .Include(t => t.AssignedBy)
            .Where(t => t.StoreId == RequiredStoreId && t.IsActive);

        if (fromDate.HasValue) query = query.Where(t => t.CreatedAt >= fromDate.Value);
        if (toDate.HasValue) query = query.Where(t => t.CreatedAt <= toDate.Value);
        if (branchId.HasValue)
        {
            var branchScope = await BranchQueryHelper.ResolveEmployeeScopeAsync(
                _dbContext, RequiredStoreId, branchId, true);
            query = TaskWorkflowHelper.ApplyBranchFilter(query, branchScope);
        }

        var tasks = await query
            .OrderByDescending(t => t.CreatedAt)
            .Take(5000)
            .ToListAsync();

        var sb = new StringBuilder();
        sb.AppendLine("MaCV,TieuDe,TrangThai,UuTien,NguoiGiao,NguoiNhan,Han,PhanTram,TaoLuc");
        foreach (var t in tasks)
        {
            var assignee = t.Assignee != null
                ? $"{t.Assignee.LastName} {t.Assignee.FirstName}".Trim()
                : "";
            var due = t.DueDate?.ToString("yyyy-MM-dd") ?? "";
            sb.AppendLine(string.Join(",",
                EscapeCsv(t.TaskCode),
                EscapeCsv(t.Title),
                t.Status.ToString(),
                t.Priority.ToString(),
                EscapeCsv(t.AssignedBy?.UserName),
                EscapeCsv(assignee),
                due,
                t.Progress.ToString(),
                t.CreatedAt.ToString("yyyy-MM-dd HH:mm")));
        }

        var bytes = Encoding.UTF8.GetPreamble().Concat(Encoding.UTF8.GetBytes(sb.ToString())).ToArray();
        return File(bytes, "text/csv; charset=utf-8", $"tasks-{DateTime.Now:yyyyMMdd}.csv");
    }

    [HttpPost("sla-reminders/run")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("Task", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<int>>> RunSlaReminders()
    {
        var now = DateTime.Now;
        var tasks = await _dbContext.WorkTasks
            .Where(t => t.StoreId == RequiredStoreId && t.IsActive &&
                t.DueDate != null &&
                t.Status != WorkTaskStatus.Completed &&
                t.Status != WorkTaskStatus.Cancelled &&
                t.AssigneeId != null)
            .ToListAsync();

        var sent = 0;
        foreach (var task in tasks)
        {
            var hours = task.SlaReminderHours ?? 24;
            var remindAt = task.DueDate!.Value.AddHours(-hours);
            if (now < remindAt || now > task.DueDate) continue;

            var userId = await ResolveUserIdFromEmployeeId(task.AssigneeId!.Value);
            if (!userId.HasValue) continue;

            await notificationService.CreateAndSendAsync(
                userId.Value, NotificationType.Reminder,
                "Nhắc deadline công việc",
                $"\"{task.Title}\" sắp đến hạn ({task.DueDate:dd/MM/yyyy HH:mm})",
                relatedEntityId: task.Id, relatedEntityType: "WorkTask",
                fromUserId: CurrentUserId, categoryCode: "task", storeId: RequiredStoreId);
            sent++;
        }

        return Ok(AppResponse<int>.Success(sent));
    }

    private static string EscapeCsv(string? value)
    {
        if (string.IsNullOrEmpty(value)) return "";
        if (value.Contains(',') || value.Contains('"'))
            return $"\"{value.Replace("\"", "\"\"")}\"";
        return value;
    }

    private async Task SyncTaskDependenciesAsync(Guid taskId, IEnumerable<Guid> dependsOnIds)
    {
        var ids = dependsOnIds.Where(id => id != Guid.Empty && id != taskId).Distinct().ToList();
        var existing = await _dbContext.TaskDependencies
            .Where(d => d.TaskId == taskId)
            .ToListAsync();

        foreach (var row in existing.Where(e => !ids.Contains(e.DependsOnTaskId)))
            _dbContext.TaskDependencies.Remove(row);

        var existingIds = existing.Select(e => e.DependsOnTaskId).ToHashSet();
        foreach (var depId in ids.Where(id => !existingIds.Contains(id)))
        {
            _dbContext.TaskDependencies.Add(new TaskDependency
            {
                Id = Guid.NewGuid(),
                TaskId = taskId,
                DependsOnTaskId = depId
            });
        }
    }

    private async Task<List<string>> GetIncompleteBlockersAsync(Guid taskId)
    {
        return await _dbContext.TaskDependencies
            .Include(d => d.DependsOnTask)
            .Where(d => d.TaskId == taskId &&
                d.DependsOnTask != null &&
                d.DependsOnTask.Status != WorkTaskStatus.Completed)
            .Select(d => d.DependsOnTask!.Title)
            .ToListAsync();
    }
}

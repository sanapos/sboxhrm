using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.DTOs.Tasks;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Infrastructure.Services;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>Công việc v2: giai đoạn theo ngành, checklist có ảnh, tải việc, dòng thời gian, thống kê, mẫu lặp.</summary>
public partial class TasksController
{
    // ─── Dự án + giai đoạn ────────────────────────────────────────

    /// <summary>
    /// Gắn dự án / giai đoạn cho việc. Giai đoạn phải thuộc quy trình của dự án;
    /// chưa chọn giai đoạn → giai đoạn đầu. Trả về thông báo lỗi hoặc null.
    /// </summary>
    private async Task<string?> ApplyProjectAndStageAsync(WorkTask task, Guid? projectId, string? stageKey)
    {
        if (projectId == null)
        {
            task.ProjectId = null;
            task.StageKey = null;
            return null;
        }
        var project = await _dbContext.TaskProjects.AsNoTracking()
            .FirstOrDefaultAsync(p => p.Id == projectId && p.StoreId == RequiredStoreId);
        if (project == null) return "Không tìm thấy dự án";
        task.ProjectId = project.Id;
        var stages = TaskV2Helper.ParseStages(project.Stages);
        if (stages.Count == 0)
        {
            task.StageKey = null;
            return null;
        }
        var key = string.IsNullOrWhiteSpace(stageKey) ? null : stageKey.Trim();
        var stage = key == null ? null : stages.FirstOrDefault(s => s.Key == key);
        if (key != null && stage == null) return "Giai đoạn không thuộc quy trình của dự án";
        task.StageKey = (stage ?? stages[0]).Key;
        return null;
    }

    /// <summary>Hoàn thành → chuyển sang giai đoạn «xong» đầu tiên; mở lại từ giai đoạn xong → giai đoạn trước đó.</summary>
    private async Task SyncStageWithStatusAsync(WorkTask task)
    {
        if (task.ProjectId == null) return;
        var raw = await _dbContext.TaskProjects.AsNoTracking()
            .Where(p => p.Id == task.ProjectId).Select(p => p.Stages).FirstOrDefaultAsync();
        var stages = TaskV2Helper.ParseStages(raw);
        if (stages.Count == 0) return;
        var current = stages.FirstOrDefault(s => s.Key == task.StageKey);
        if (task.Status == WorkTaskStatus.Completed)
        {
            if (current is { Done: true }) return;
            var idx = current == null ? -1 : stages.IndexOf(current);
            var doneStage = stages.Skip(idx + 1).FirstOrDefault(s => s.Done) ?? stages.FirstOrDefault(s => s.Done);
            if (doneStage != null) task.StageKey = doneStage.Key;
        }
        else if (current is { Done: true } && task.Status != WorkTaskStatus.Cancelled)
        {
            var idx = stages.IndexOf(current);
            var back = stages.Take(idx).LastOrDefault(s => !s.Done) ?? stages.FirstOrDefault(s => !s.Done);
            if (back != null) task.StageKey = back.Key;
        }
    }

    /// <summary>Kéo việc sang giai đoạn khác (bảng Kanban theo ngành).</summary>
    [HttpPatch("{id}/stage")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("Task", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<WorkTaskDto>>> MoveTaskStage(Guid id, [FromBody] MoveTaskStageDto request)
    {
        var task = await _dbContext.WorkTasks.AsTracking()
            .FirstOrDefaultAsync(t => t.Id == id && t.StoreId == RequiredStoreId);
        if (task == null) return Ok(AppResponse<WorkTaskDto>.Error("Không tìm thấy công việc"));
        if (!await TaskWorkflowHelper.CanModifyTaskAsync(_dbContext, task, CurrentUserId, RequiredStoreId, User))
            return Ok(AppResponse<WorkTaskDto>.Error("Bạn không có quyền cập nhật công việc này"));
        if (task.ProjectId == null)
            return Ok(AppResponse<WorkTaskDto>.Error("Công việc chưa thuộc dự án nào"));

        var raw = await _dbContext.TaskProjects.AsNoTracking()
            .Where(p => p.Id == task.ProjectId).Select(p => p.Stages).FirstOrDefaultAsync();
        var stages = TaskV2Helper.ParseStages(raw);
        var target = stages.FirstOrDefault(s => s.Key == request.StageKey);
        if (target == null) return Ok(AppResponse<WorkTaskDto>.Error("Giai đoạn không hợp lệ"));
        if (task.StageKey == target.Key)
            return Ok(AppResponse<WorkTaskDto>.Success(MapToDto(task)));

        var oldStage = stages.FirstOrDefault(s => s.Key == task.StageKey);
        if (!target.Done && task.Status is WorkTaskStatus.Todo)
        {
            var blocked = await GetIncompleteBlockersAsync(task.Id);
            if (blocked.Count > 0 && stages.IndexOf(target) > (oldStage == null ? -1 : stages.IndexOf(oldStage)))
                return Ok(AppResponse<WorkTaskDto>.Error($"Công việc bị chặn bởi: {string.Join(", ", blocked)}"));
        }

        var oldStatus = task.Status;
        task.StageKey = target.Key;
        if (target.Done)
        {
            task.Status = WorkTaskStatus.Completed;
            task.CompletedDate ??= DateTime.Now;
            task.Progress = 100;
        }
        else
        {
            if (task.Status is WorkTaskStatus.Completed or WorkTaskStatus.Cancelled)
            {
                task.Status = WorkTaskStatus.InProgress;
                task.CompletedDate = null;
                if (TaskV2Helper.AutoProgress(task) is int p) task.Progress = p;
            }
            else if (task.Status is WorkTaskStatus.Todo && stages.IndexOf(target) > 0)
            {
                task.Status = WorkTaskStatus.InProgress;
            }
            if (task.Status == WorkTaskStatus.InProgress) task.ActualStartDate ??= DateTime.Now;
        }
        task.UpdatedAt = DateTime.Now;
        task.UpdatedBy = CurrentUserEmail;
        _dbContext.TaskHistories.Add(CreateHistory(task.Id, "StageChanged", oldStage?.Name ?? task.StageKey, target.Name));
        if (oldStatus != task.Status)
            _dbContext.TaskHistories.Add(CreateHistory(task.Id, "StatusChanged", oldStatus.ToString(), task.Status.ToString()));
        await TaskV2Helper.RecalcParentAsync(_dbContext, task.ParentTaskId);
        await _dbContext.SaveChangesAsync();

        if (target.Done && task.AssignedById != CurrentUserId)
        {
            try
            {
                await notificationService.CreateAndSendAsync(
                    task.AssignedById, NotificationType.Success,
                    "Công việc hoàn thành",
                    $"\"{task.Title}\" đã chuyển sang «{target.Name}»",
                    relatedEntityId: task.Id, relatedEntityType: "WorkTask",
                    fromUserId: CurrentUserId, categoryCode: "task", storeId: RequiredStoreId);
            }
            catch { /* thông báo lỗi không ảnh hưởng thao tác chính */ }
        }

        var reloaded = await _dbContext.WorkTasks
            .Include(t => t.Assignee).Include(t => t.AssignedBy).Include(t => t.Project)
            .FirstAsync(t => t.Id == task.Id);
        return Ok(AppResponse<WorkTaskDto>.Success(MapToDto(reloaded)));
    }

    // ─── Checklist ───────────────────────────────────────────────

    /// <summary>
    /// Đánh dấu một mục checklist (người làm, giờ làm, ảnh). Mục bắt buộc ảnh cần PhotoUrl.
    /// Chế độ tiến độ theo checklist → tự cập nhật %.
    /// </summary>
    [HttpPatch("{id}/checklist/{itemId}")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("Task", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<WorkTaskDto>>> ToggleChecklistItem(
        Guid id, string itemId, [FromBody] ToggleChecklistItemDto request)
    {
        var task = await _dbContext.WorkTasks.AsTracking()
            .FirstOrDefaultAsync(t => t.Id == id && t.StoreId == RequiredStoreId);
        if (task == null) return Ok(AppResponse<WorkTaskDto>.Error("Không tìm thấy công việc"));
        if (!await TaskWorkflowHelper.CanModifyTaskAsync(_dbContext, task, CurrentUserId, RequiredStoreId, User))
            return Ok(AppResponse<WorkTaskDto>.Error("Bạn không có quyền cập nhật công việc này"));
        if (task.Status is WorkTaskStatus.Cancelled)
            return Ok(AppResponse<WorkTaskDto>.Error("Công việc đã hủy"));

        var items = TaskV2Helper.ParseChecklist(task.Checklist);
        var item = items.FirstOrDefault(i => i.Id == itemId);
        if (item == null) return Ok(AppResponse<WorkTaskDto>.Error("Không tìm thấy mục checklist"));

        var photo = string.IsNullOrWhiteSpace(request.PhotoUrl) ? item.PhotoUrl : request.PhotoUrl.Trim();
        if (request.Done && item.RequirePhoto && string.IsNullOrWhiteSpace(photo))
            return Ok(AppResponse<WorkTaskDto>.Error($"Mục «{item.Text}» cần chụp ảnh trước khi đánh dấu xong"));

        var employee = await TaskWorkflowHelper.GetEmployeeForUserAsync(_dbContext, RequiredStoreId, CurrentUserId);
        item.Done = request.Done;
        item.PhotoUrl = photo;
        if (request.Note != null) item.Note = string.IsNullOrWhiteSpace(request.Note) ? null : request.Note.Trim();
        if (request.Done)
        {
            item.DoneAt = DateTime.Now;
            item.DoneById = CurrentUserId;
            item.DoneBy = employee != null ? $"{employee.LastName} {employee.FirstName}".Trim() : CurrentUserEmail;
        }
        else
        {
            item.DoneAt = null;
            item.DoneById = null;
            item.DoneBy = null;
        }
        task.Checklist = TaskV2Helper.SerializeChecklist(items);
        var oldProgress = task.Progress;
        if (task.ProgressMode == TaskProgressMode.Checklist && TaskV2Helper.AutoProgress(task) is int p)
            task.Progress = task.Status == WorkTaskStatus.Completed ? 100 : p;
        if (request.Done && task.Status is WorkTaskStatus.Todo)
        {
            task.Status = WorkTaskStatus.InProgress;
            task.ActualStartDate ??= DateTime.Now;
        }
        task.UpdatedAt = DateTime.Now;
        task.UpdatedBy = CurrentUserEmail;
        _dbContext.TaskHistories.Add(CreateHistory(task.Id, "ChecklistUpdated",
            null, $"{(request.Done ? "✓" : "✗")} {item.Text}"));
        if (oldProgress != task.Progress)
            _dbContext.TaskHistories.Add(CreateHistory(task.Id, "ProgressUpdated", oldProgress.ToString(), task.Progress.ToString()));
        await _dbContext.SaveChangesAsync();

        var reloaded = await _dbContext.WorkTasks
            .Include(t => t.Assignee).Include(t => t.AssignedBy).Include(t => t.Project)
            .FirstAsync(t => t.Id == task.Id);
        return Ok(AppResponse<WorkTaskDto>.Success(MapToDto(reloaded)));
    }

    // ─── Tải việc theo nhân viên ─────────────────────────────────

    [HttpGet("workload")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("Task", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<TaskWorkloadDto>>>> GetWorkload(
        [FromQuery] DateTime? from = null, [FromQuery] DateTime? to = null, [FromQuery] Guid? projectId = null)
    {
        var now = DateTime.Now;
        var f = from ?? now.Date.AddDays(-29);
        var t = (to ?? now).Date.AddDays(1);
        var query = _dbContext.WorkTasks.AsNoTracking().Where(x => x.StoreId == RequiredStoreId && x.IsActive);
        query = await TaskWorkflowHelper.ApplyViewerScopeAsync(query, _dbContext, RequiredStoreId, CurrentUserId, User);
        if (projectId.HasValue) query = query.Where(x => x.ProjectId == projectId);

        // Người phụ trách chính + người được giao thêm.
        var rows = await query
            .Where(x => x.Status != WorkTaskStatus.Cancelled &&
                        (x.Status != WorkTaskStatus.Completed || (x.CompletedDate >= f && x.CompletedDate < t)))
            .Select(x => new
            {
                x.AssigneeId,
                Extra = x.TaskAssignees!.Select(a => a.EmployeeId).ToList(),
                x.Status,
                x.DueDate,
                x.CompletedDate,
                x.EstimatedHours,
            })
            .ToListAsync();

        var map = new Dictionary<Guid, TaskWorkloadDto>();
        foreach (var r in rows)
        {
            var people = new HashSet<Guid>(r.Extra);
            if (r.AssigneeId.HasValue) people.Add(r.AssigneeId.Value);
            foreach (var emp in people)
            {
                if (!map.TryGetValue(emp, out var w)) map[emp] = w = new TaskWorkloadDto { EmployeeId = emp };
                if (r.Status == WorkTaskStatus.Completed)
                {
                    w.CompletedInRange++;
                    if (r.DueDate == null || r.CompletedDate <= r.DueDate) w.CompletedOnTime++;
                    continue;
                }
                w.Open++;
                if (r.Status == WorkTaskStatus.InProgress) w.InProgress++;
                if (r.DueDate < now) w.Overdue++;
                else if (r.DueDate < now.AddHours(48)) w.DueSoon++;
                w.OpenEstimatedHours += r.EstimatedHours ?? 0;
            }
        }
        var ids = map.Keys.ToList();
        var names = await _dbContext.Employees.AsNoTracking()
            .Where(e => ids.Contains(e.Id))
            .Select(e => new { e.Id, e.LastName, e.FirstName, e.EmployeeCode })
            .ToListAsync();
        foreach (var n in names)
        {
            map[n.Id].EmployeeName = $"{n.LastName} {n.FirstName}".Trim();
            map[n.Id].EmployeeCode = n.EmployeeCode;
        }
        foreach (var w in map.Values)
        {
            if (string.IsNullOrEmpty(w.EmployeeName)) w.EmployeeName = "—";
            w.OnTimeRate = w.CompletedInRange == 0 ? 0 : Math.Round(w.CompletedOnTime * 100.0 / w.CompletedInRange, 1);
        }
        return Ok(AppResponse<List<TaskWorkloadDto>>.Success(
            map.Values.OrderByDescending(w => w.Overdue).ThenByDescending(w => w.Open).ToList()));
    }

    // ─── Dòng thời gian (Gantt) ──────────────────────────────────

    [HttpGet("timeline")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("Task", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<TaskTimelineItemDto>>>> GetTimeline(
        [FromQuery] Guid? projectId = null, [FromQuery] DateTime? from = null, [FromQuery] DateTime? to = null,
        [FromQuery] bool includeCompleted = true)
    {
        var f = from ?? DateTime.Now.Date.AddDays(-14);
        var t = (to ?? DateTime.Now.Date.AddDays(45)).Date.AddDays(1);
        var query = _dbContext.WorkTasks.AsNoTracking().Where(x => x.StoreId == RequiredStoreId && x.IsActive);
        query = await TaskWorkflowHelper.ApplyViewerScopeAsync(query, _dbContext, RequiredStoreId, CurrentUserId, User);
        if (projectId.HasValue) query = query.Where(x => x.ProjectId == projectId);
        if (!includeCompleted) query = query.Where(x => x.Status != WorkTaskStatus.Completed);
        query = query.Where(x => x.Status != WorkTaskStatus.Cancelled &&
                                 (x.StartDate ?? x.CreatedAt) < t &&
                                 (x.DueDate ?? x.CompletedDate ?? DateTime.MaxValue) >= f);
        var items = await query
            .OrderBy(x => x.StartDate ?? x.CreatedAt)
            .Take(500)
            .Select(x => new TaskTimelineItemDto
            {
                Id = x.Id,
                TaskCode = x.TaskCode,
                Title = x.Title,
                Status = x.Status,
                Priority = x.Priority,
                Progress = x.Progress,
                StartDate = x.StartDate,
                DueDate = x.DueDate,
                CompletedDate = x.CompletedDate,
                CreatedAt = x.CreatedAt,
                StageKey = x.StageKey,
                ProjectId = x.ProjectId,
                ProjectName = x.Project != null ? x.Project.Name : null,
                ParentTaskId = x.ParentTaskId,
                AssigneeName = x.Assignee != null ? x.Assignee.LastName + " " + x.Assignee.FirstName : null,
            })
            .ToListAsync();
        var ids = items.Select(i => i.Id).ToList();
        var deps = await _dbContext.TaskDependencies.AsNoTracking()
            .Where(d => ids.Contains(d.TaskId))
            .Select(d => new { d.TaskId, d.DependsOnTaskId })
            .ToListAsync();
        var byTask = deps.GroupBy(d => d.TaskId).ToDictionary(g => g.Key, g => g.Select(x => x.DependsOnTaskId).ToList());
        foreach (var i in items)
            if (byTask.TryGetValue(i.Id, out var b)) i.BlockedBy = b;
        return Ok(AppResponse<List<TaskTimelineItemDto>>.Success(items));
    }

    // ─── Thống kê tổng quan ──────────────────────────────────────

    [HttpGet("insights")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("Task", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<TaskInsightsDto>>> GetInsights(
        [FromQuery] DateTime? from = null, [FromQuery] DateTime? to = null,
        [FromQuery] Guid? projectId = null, [FromQuery] bool onlyMine = false)
    {
        var now = DateTime.Now;
        var f = (from ?? now.Date.AddDays(-13)).Date;
        var t = (to ?? now).Date.AddDays(1);
        var span = t - f;
        var query = _dbContext.WorkTasks.AsNoTracking().Where(x => x.StoreId == RequiredStoreId && x.IsActive);
        query = await TaskWorkflowHelper.ApplyViewerScopeAsync(query, _dbContext, RequiredStoreId, CurrentUserId, User);
        if (projectId.HasValue) query = query.Where(x => x.ProjectId == projectId);
        if (onlyMine)
        {
            var emp = await TaskWorkflowHelper.GetEmployeeForUserAsync(_dbContext, RequiredStoreId, CurrentUserId);
            if (emp == null) return Ok(AppResponse<TaskInsightsDto>.Success(new TaskInsightsDto()));
            query = query.Where(x => x.AssigneeId == emp.Id || x.TaskAssignees!.Any(a => a.EmployeeId == emp.Id));
        }

        var dto = new TaskInsightsDto();
        var statusCounts = await query.GroupBy(x => x.Status).Select(g => new { g.Key, N = g.Count() }).ToListAsync();
        foreach (var s in statusCounts) dto.ByStatus[s.Key.ToString()] = s.N;
        int C(WorkTaskStatus s) => statusCounts.FirstOrDefault(x => x.Key == s)?.N ?? 0;
        dto.Total = statusCounts.Sum(x => x.N);
        dto.InProgress = C(WorkTaskStatus.InProgress);
        dto.PendingAcceptance = C(WorkTaskStatus.Assigned);
        dto.InReview = C(WorkTaskStatus.InReview);
        dto.Open = C(WorkTaskStatus.Todo) + dto.InProgress + dto.PendingAcceptance + dto.InReview + C(WorkTaskStatus.OnHold);

        var openQuery = query.Where(x => x.Status != WorkTaskStatus.Completed && x.Status != WorkTaskStatus.Cancelled);
        dto.Overdue = await openQuery.CountAsync(x => x.DueDate < now);
        dto.DueToday = await openQuery.CountAsync(x => x.DueDate >= now && x.DueDate < now.Date.AddDays(1));

        var typeCounts = await openQuery.GroupBy(x => x.TaskType).Select(g => new { g.Key, N = g.Count() }).ToListAsync();
        foreach (var s in typeCounts) dto.ByType[s.Key.ToString()] = s.N;

        var done = await query
            .Where(x => x.Status == WorkTaskStatus.Completed && x.CompletedDate >= f && x.CompletedDate < t)
            .Select(x => new { x.CompletedDate, x.DueDate, x.CreatedAt })
            .ToListAsync();
        dto.CompletedInRange = done.Count;
        dto.CompletedOnTime = done.Count(d => d.DueDate == null || d.CompletedDate <= d.DueDate);
        dto.OnTimeRate = done.Count == 0 ? 0 : Math.Round(dto.CompletedOnTime * 100.0 / done.Count, 1);
        dto.AvgCycleHours = done.Count == 0 ? 0 : Math.Round(done.Average(d => (d.CompletedDate!.Value - d.CreatedAt).TotalHours), 1);
        dto.CompletedPrevRange = await query.CountAsync(x =>
            x.Status == WorkTaskStatus.Completed && x.CompletedDate >= f - span && x.CompletedDate < f);

        var created = await query.Where(x => x.CreatedAt >= f && x.CreatedAt < t)
            .Select(x => x.CreatedAt).ToListAsync();
        for (var d = f; d < t; d = d.AddDays(1))
        {
            var next = d.AddDays(1);
            var day = done.Where(x => x.CompletedDate >= d && x.CompletedDate < next).ToList();
            dto.ByDay.Add(new TaskInsightDayDto
            {
                Date = d,
                Created = created.Count(c => c >= d && c < next),
                Completed = day.Count,
                CompletedLate = day.Count(x => x.DueDate != null && x.CompletedDate > x.DueDate),
            });
        }
        dto.ActiveProjects = await _dbContext.TaskProjects.AsNoTracking()
            .CountAsync(p => p.StoreId == RequiredStoreId && p.Status == TaskProjectStatus.Active);
        return Ok(AppResponse<TaskInsightsDto>.Success(dto));
    }

    // ─── Mẫu việc: sửa / xóa / lịch lặp ───────────────────────────

    private void ApplyTemplateV2(TaskTemplate entity, CreateTaskTemplateDto request)
    {
        entity.StageKey = string.IsNullOrWhiteSpace(request.StageKey) ? null : request.StageKey.Trim();
        entity.ProgressMode = request.ProgressMode;
        entity.ProjectId = request.ProjectId;
        entity.RecurrenceType = request.RecurrenceType;
        entity.RecurrenceDays = string.IsNullOrWhiteSpace(request.RecurrenceDays) ? null : request.RecurrenceDays.Trim();
        entity.RecurrenceTime = string.IsNullOrWhiteSpace(request.RecurrenceTime) ? null : request.RecurrenceTime.Trim();
        entity.DueAfterHours = request.DueAfterHours;
        var assignees = request.DefaultAssigneeIds?.Where(g => g != Guid.Empty).Distinct().ToList();
        entity.DefaultAssigneeIds = assignees == null || assignees.Count == 0
            ? null
            : System.Text.Json.JsonSerializer.Serialize(assignees);
        entity.NextRunAt = TaskV2Helper.NextRun(entity.RecurrenceType, entity.RecurrenceDays, entity.RecurrenceTime, DateTime.Now);
    }

    private static TaskTemplateDto ToTemplateDto(TaskTemplate e) => new()
    {
        Id = e.Id,
        Name = e.Name,
        Title = e.Title,
        Description = e.Description,
        TaskType = e.TaskType,
        Priority = e.Priority,
        EstimatedHours = e.EstimatedHours,
        DefaultSlaReminderHours = e.DefaultSlaReminderHours,
        Tags = e.Tags,
        Checklist = e.Checklist,
        IsActive = e.IsActive,
        IndustryKey = e.IndustryKey,
        StageKey = e.StageKey,
        ProgressMode = e.ProgressMode,
        ProjectId = e.ProjectId,
        RecurrenceType = e.RecurrenceType,
        RecurrenceDays = e.RecurrenceDays,
        RecurrenceTime = e.RecurrenceTime,
        DueAfterHours = e.DueAfterHours,
        DefaultAssigneeIds = TaskV2Helper.ParseGuidList(e.DefaultAssigneeIds),
        NextRunAt = e.NextRunAt,
        LastRunAt = e.LastRunAt,
    };

    [HttpPut("templates/{templateId}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("Task", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<TaskTemplateDto>>> UpdateTemplate(
        Guid templateId, [FromBody] CreateTaskTemplateDto request)
    {
        var entity = await _dbContext.TaskTemplates.AsTracking()
            .FirstOrDefaultAsync(t => t.Id == templateId && t.StoreId == RequiredStoreId);
        if (entity == null) return Ok(AppResponse<TaskTemplateDto>.Error("Không tìm thấy mẫu"));
        if (string.IsNullOrWhiteSpace(request.Name) || string.IsNullOrWhiteSpace(request.Title))
            return Ok(AppResponse<TaskTemplateDto>.Error("Nhập tên mẫu và tiêu đề công việc"));
        entity.Name = request.Name.Trim();
        entity.Title = request.Title.Trim();
        entity.Description = request.Description;
        entity.TaskType = request.TaskType;
        entity.Priority = request.Priority;
        entity.EstimatedHours = request.EstimatedHours;
        entity.DefaultSlaReminderHours = request.DefaultSlaReminderHours;
        entity.Tags = request.Tags;
        entity.Checklist = TaskV2Helper.NormalizeChecklist(request.Checklist);
        ApplyTemplateV2(entity, request);
        entity.UpdatedAt = DateTime.Now;
        entity.UpdatedBy = CurrentUserEmail;
        await _dbContext.SaveChangesAsync();
        return Ok(AppResponse<TaskTemplateDto>.Success(ToTemplateDto(entity)));
    }

    [HttpDelete("templates/{templateId}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("Task", ModulePermissionAction.Delete)]
    public async Task<ActionResult<AppResponse<bool>>> DeleteTemplate(Guid templateId)
    {
        var entity = await _dbContext.TaskTemplates.AsTracking()
            .FirstOrDefaultAsync(t => t.Id == templateId && t.StoreId == RequiredStoreId);
        if (entity == null) return Ok(AppResponse<bool>.Error("Không tìm thấy mẫu"));
        entity.IsActive = false;
        entity.RecurrenceType = TaskRecurrenceType.None;
        entity.NextRunAt = null;
        entity.Deleted = DateTime.Now;
        entity.DeletedBy = CurrentUserEmail;
        await _dbContext.SaveChangesAsync();
        return Ok(AppResponse<bool>.Success(true));
    }

    /// <summary>Tạo ngay các việc của mẫu lặp (không chờ lịch) — để thử cấu hình.</summary>
    [HttpPost("templates/{templateId}/run-now")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("Task", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<int>>> RunTemplateNow(Guid templateId)
    {
        var entity = await _dbContext.TaskTemplates.AsTracking()
            .FirstOrDefaultAsync(t => t.Id == templateId && t.StoreId == RequiredStoreId && t.IsActive);
        if (entity == null) return Ok(AppResponse<int>.Error("Không tìm thấy mẫu"));
        if (TaskV2Helper.ParseGuidList(entity.DefaultAssigneeIds).Count == 0)
            return Ok(AppResponse<int>.Error("Mẫu chưa chọn nhân viên nhận việc"));
        var n = await TaskRecurrenceRunner.CreateTasksFromTemplateAsync(
            _dbContext, entity, DateTime.Now, CurrentUserId, notificationService);
        await _dbContext.SaveChangesAsync();
        return Ok(AppResponse<int>.Success(n));
    }
}

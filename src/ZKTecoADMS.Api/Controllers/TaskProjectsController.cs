using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.DTOs.Tasks;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Services;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// Dự án / công trình / đơn việc (Công việc v2) và gói mẫu theo ngành.
/// </summary>
[ApiController]
[Route("api/task-projects")]
[Authorize]
public class TaskProjectsController(ZKTecoDbContext db) : AuthenticatedControllerBase
{
    private static TaskStageDto ToDto(TaskStage s) => new() { Key = s.Key, Name = s.Name, Color = s.Color, Done = s.Done };
    private static TaskStage FromDto(TaskStageDto s) => new() { Key = s.Key.Trim(), Name = s.Name.Trim(), Color = s.Color, Done = s.Done };

    /// <summary>Danh sách dự án kèm tiến độ. Nhân viên chỉ thấy dự án mình phụ trách hoặc có việc.</summary>
    [HttpGet]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("Task", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<TaskProjectDto>>>> List(
        [FromQuery] TaskProjectStatus? status = null, [FromQuery] string? search = null,
        [FromQuery] bool includeClosed = false)
    {
        var storeId = RequiredStoreId;
        var q = db.TaskProjects.AsNoTracking().Where(p => p.StoreId == storeId);
        if (status.HasValue) q = q.Where(p => p.Status == status);
        else if (!includeClosed) q = q.Where(p => p.Status == TaskProjectStatus.Active || p.Status == TaskProjectStatus.OnHold);
        if (!string.IsNullOrWhiteSpace(search))
        {
            var s = $"%{search.Trim()}%";
            q = q.Where(p => EF.Functions.ILike(p.Name, s) || EF.Functions.ILike(p.Code, s) ||
                             (p.CustomerName != null && EF.Functions.ILike(p.CustomerName, s)) ||
                             (p.CustomerPhone != null && EF.Functions.ILike(p.CustomerPhone, s)));
        }
        if (!TaskWorkflowHelper.IsManagerOrAdmin(User))
        {
            var emp = await TaskWorkflowHelper.GetEmployeeForUserAsync(db, storeId, CurrentUserId);
            if (emp == null) return Ok(AppResponse<List<TaskProjectDto>>.Success(new()));
            q = q.Where(p => p.OwnerEmployeeId == emp.Id ||
                             p.Tasks!.Any(t => t.IsActive && (t.AssigneeId == emp.Id || t.TaskAssignees!.Any(a => a.EmployeeId == emp.Id))));
        }
        var projects = await q.Include(p => p.OwnerEmployee)
            .OrderBy(p => p.Status).ThenBy(p => p.DueDate == null).ThenBy(p => p.DueDate).ThenByDescending(p => p.CreatedAt)
            .Take(300)
            .ToListAsync();
        var list = await WithStatsAsync(projects, withStageCounts: false);
        return Ok(AppResponse<List<TaskProjectDto>>.Success(list));
    }

    [HttpGet("{id:guid}")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("Task", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<TaskProjectDto>>> Get(Guid id)
    {
        var p = await db.TaskProjects.AsNoTracking().Include(x => x.OwnerEmployee)
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == RequiredStoreId);
        if (p == null) return Ok(AppResponse<TaskProjectDto>.Error("Không tìm thấy dự án"));
        var dto = (await WithStatsAsync(new List<TaskProject> { p }, withStageCounts: true)).First();
        return Ok(AppResponse<TaskProjectDto>.Success(dto));
    }

    [HttpPost]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("Task", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<TaskProjectDto>>> Create([FromBody] SaveTaskProjectDto request)
    {
        if (string.IsNullOrWhiteSpace(request.Name))
            return Ok(AppResponse<TaskProjectDto>.Error("Nhập tên dự án"));
        var storeId = RequiredStoreId;
        var pack = TaskIndustryPacks.Find(request.IndustryKey);
        var stages = request.Stages is { Count: > 0 }
            ? request.Stages.Where(s => !string.IsNullOrWhiteSpace(s.Key) && !string.IsNullOrWhiteSpace(s.Name)).Select(FromDto).ToList()
            : pack?.Stages.ToList() ?? new List<TaskStage>();
        var code = string.IsNullOrWhiteSpace(request.Code)
            ? await TaskV2Helper.GenerateProjectCodeAsync(db, storeId)
            : request.Code.Trim().ToUpperInvariant();
        if (await db.TaskProjects.IgnoreQueryFilters().AnyAsync(p => p.StoreId == storeId && p.Code == code))
            return Ok(AppResponse<TaskProjectDto>.Error($"Mã {code} đã tồn tại"));
        var ownerError = await ValidateOwnerAsync(request.OwnerEmployeeId);
        if (ownerError != null) return Ok(AppResponse<TaskProjectDto>.Error(ownerError));

        var project = new TaskProject
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            Code = code,
            Name = request.Name.Trim(),
            Description = request.Description,
            IndustryKey = pack?.Key ?? request.IndustryKey,
            Color = request.Color ?? pack?.Color,
            Status = request.Status ?? TaskProjectStatus.Active,
            OwnerEmployeeId = request.OwnerEmployeeId,
            BranchId = request.BranchId,
            CustomerName = request.CustomerName?.Trim(),
            CustomerPhone = request.CustomerPhone?.Trim(),
            Address = request.Address?.Trim(),
            Budget = request.Budget,
            StartDate = request.StartDate,
            DueDate = request.DueDate,
            Stages = TaskV2Helper.SerializeStages(stages),
            IsActive = true,
            CreatedBy = CurrentUserEmail,
        };
        db.TaskProjects.Add(project);

        // Tạo sẵn các việc không lặp của gói ngành, mỗi việc ở đúng giai đoạn.
        if (request.CreateTasksFromPack && pack != null)
        {
            var offset = 0;
            foreach (var t in pack.Templates.Where(t => t.Recurrence == TaskRecurrenceType.None))
            {
                var task = new WorkTask
                {
                    Id = Guid.NewGuid(),
                    TaskCode = await TaskWorkflowHelper.GenerateTaskCodeAsync(db, storeId, offset++),
                    Title = t.Name,
                    Description = t.Description,
                    TaskType = t.Type,
                    Priority = t.Priority,
                    Status = WorkTaskStatus.Todo,
                    StoreId = storeId,
                    AssignedById = CurrentUserId,
                    AssigneeId = request.OwnerEmployeeId,
                    ProjectId = project.Id,
                    StageKey = stages.Any(s => s.Key == t.StageKey) ? t.StageKey : stages.FirstOrDefault()?.Key,
                    EstimatedHours = t.Hours,
                    Checklist = TaskIndustryPacks.ChecklistJson(t),
                    ProgressMode = TaskProgressMode.Checklist,
                    Location = project.Address,
                    SlaReminderHours = 24,
                    IsActive = true,
                    CreatedBy = CurrentUserEmail,
                };
                db.WorkTasks.Add(task);
                if (request.OwnerEmployeeId.HasValue)
                    await TaskWorkflowHelper.SyncAssigneesAsync(db, task.Id, request.OwnerEmployeeId, new List<Guid> { request.OwnerEmployeeId.Value });
            }
        }
        await db.SaveChangesAsync();
        return await Get(project.Id);
    }

    [HttpPut("{id:guid}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("Task", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<TaskProjectDto>>> Update(Guid id, [FromBody] SaveTaskProjectDto request)
    {
        var p = await db.TaskProjects.AsTracking().FirstOrDefaultAsync(x => x.Id == id && x.StoreId == RequiredStoreId);
        if (p == null) return Ok(AppResponse<TaskProjectDto>.Error("Không tìm thấy dự án"));
        if (string.IsNullOrWhiteSpace(request.Name)) return Ok(AppResponse<TaskProjectDto>.Error("Nhập tên dự án"));
        var ownerError = await ValidateOwnerAsync(request.OwnerEmployeeId);
        if (ownerError != null) return Ok(AppResponse<TaskProjectDto>.Error(ownerError));

        if (request.Stages != null)
        {
            var stages = request.Stages.Where(s => !string.IsNullOrWhiteSpace(s.Key) && !string.IsNullOrWhiteSpace(s.Name))
                .Select(FromDto).GroupBy(s => s.Key).Select(g => g.First()).ToList();
            // Việc ở giai đoạn bị xóa → chuyển về giai đoạn đầu.
            var keys = stages.Select(s => s.Key).ToHashSet();
            var orphan = await db.WorkTasks.AsTracking()
                .Where(t => t.ProjectId == id && t.StageKey != null && !keys.Contains(t.StageKey))
                .ToListAsync();
            foreach (var t in orphan) t.StageKey = stages.FirstOrDefault()?.Key;
            p.Stages = TaskV2Helper.SerializeStages(stages);
        }
        if (!string.IsNullOrWhiteSpace(request.Code))
        {
            var code = request.Code.Trim().ToUpperInvariant();
            if (code != p.Code && await db.TaskProjects.IgnoreQueryFilters().AnyAsync(x => x.StoreId == p.StoreId && x.Code == code && x.Id != id))
                return Ok(AppResponse<TaskProjectDto>.Error($"Mã {code} đã tồn tại"));
            p.Code = code;
        }
        p.Name = request.Name.Trim();
        p.Description = request.Description;
        p.IndustryKey = request.IndustryKey ?? p.IndustryKey;
        p.Color = request.Color ?? p.Color;
        if (request.Status.HasValue && request.Status != p.Status)
        {
            p.Status = request.Status.Value;
            p.CompletedAt = p.Status == TaskProjectStatus.Completed ? DateTime.Now : null;
        }
        p.OwnerEmployeeId = request.OwnerEmployeeId;
        p.BranchId = request.BranchId;
        p.CustomerName = request.CustomerName?.Trim();
        p.CustomerPhone = request.CustomerPhone?.Trim();
        p.Address = request.Address?.Trim();
        p.Budget = request.Budget;
        p.StartDate = request.StartDate;
        p.DueDate = request.DueDate;
        p.UpdatedAt = DateTime.Now;
        p.UpdatedBy = CurrentUserEmail;
        await db.SaveChangesAsync();
        return await Get(id);
    }

    /// <summary>Xóa mềm dự án; công việc giữ lại nhưng bỏ gắn dự án.</summary>
    [HttpDelete("{id:guid}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("Task", ModulePermissionAction.Delete)]
    public async Task<ActionResult<AppResponse<bool>>> Delete(Guid id)
    {
        var p = await db.TaskProjects.AsTracking().FirstOrDefaultAsync(x => x.Id == id && x.StoreId == RequiredStoreId);
        if (p == null) return Ok(AppResponse<bool>.Error("Không tìm thấy dự án"));
        var tasks = await db.WorkTasks.AsTracking().Where(t => t.ProjectId == id).ToListAsync();
        foreach (var t in tasks)
        {
            t.ProjectId = null;
            t.StageKey = null;
        }
        var templates = await db.TaskTemplates.AsTracking().Where(t => t.ProjectId == id).ToListAsync();
        foreach (var t in templates) t.ProjectId = null;
        p.Deleted = DateTime.Now;
        p.DeletedBy = CurrentUserEmail;
        p.Status = TaskProjectStatus.Archived;
        await db.SaveChangesAsync();
        return Ok(AppResponse<bool>.Success(true));
    }

    // ─── Gói ngành ────────────────────────────────────────────────

    [HttpGet("industry-packs")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("Task", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<TaskIndustryPackDto>>>> Packs()
    {
        var installed = await db.TaskTemplates.AsNoTracking()
            .Where(t => t.StoreId == RequiredStoreId && t.IsActive && t.IndustryKey != null)
            .GroupBy(t => t.IndustryKey!)
            .Select(g => new { g.Key, N = g.Count() })
            .ToDictionaryAsync(x => x.Key, x => x.N);
        var list = TaskIndustryPacks.All.Select(p => new TaskIndustryPackDto
        {
            Key = p.Key,
            Name = p.Name,
            Icon = p.Icon,
            Description = p.Description,
            ProjectLabel = p.ProjectLabel,
            Color = p.Color,
            Stages = p.Stages.Select(ToDto).ToList(),
            Templates = p.Templates.Select(t => new TaskIndustryPackTemplateDto
            {
                Name = t.Name,
                TaskType = t.Type,
                StageKey = t.StageKey,
                EstimatedHours = t.Hours,
                Checklist = t.Checklist.Select(c => c.Replace("📷 ", "")).ToList(),
                PhotoItems = t.Checklist.Count(c => c.StartsWith("📷 ")),
                RecurrenceType = t.Recurrence,
                RecurrenceDays = t.RecurrenceDays,
                RecurrenceTime = t.RecurrenceTime,
            }).ToList(),
            InstalledTemplates = installed.GetValueOrDefault(p.Key),
        }).ToList();
        return Ok(AppResponse<List<TaskIndustryPackDto>>.Success(list));
    }

    /// <summary>
    /// Cài mẫu việc của gói ngành vào cửa hàng (bỏ qua mẫu trùng tên đã cài).
    /// Việc định kỳ chỉ tự chạy khi có người nhận.
    /// </summary>
    [HttpPost("industry-packs/{key}/install")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("Task", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<InstallIndustryPackResultDto>>> Install(string key, [FromBody] InstallIndustryPackDto? request)
    {
        request ??= new InstallIndustryPackDto();
        var pack = TaskIndustryPacks.Find(key);
        if (pack == null) return Ok(AppResponse<InstallIndustryPackResultDto>.Error("Không có gói ngành này"));
        var storeId = RequiredStoreId;
        var existing = await db.TaskTemplates.AsNoTracking()
            .Where(t => t.StoreId == storeId && t.IsActive && t.IndustryKey == pack.Key)
            .Select(t => t.Name).ToListAsync();
        var assignees = request.RecurringAssigneeIds?.Where(g => g != Guid.Empty).Distinct().ToList() ?? new();
        if (assignees.Count > 0)
        {
            var validCount = await db.Employees.AsNoTracking()
                .CountAsync(e => assignees.Contains(e.Id) && e.StoreId == storeId && e.Deleted == null);
            if (validCount != assignees.Count)
                return Ok(AppResponse<InstallIndustryPackResultDto>.Error("Nhân viên nhận việc không hợp lệ"));
        }
        var result = new InstallIndustryPackResultDto();
        var now = DateTime.Now;
        foreach (var t in pack.Templates)
        {
            if (existing.Contains(t.Name))
            {
                result.SkippedTemplates++;
                continue;
            }
            var recurring = request.EnableRecurring && t.Recurrence != TaskRecurrenceType.None;
            db.TaskTemplates.Add(new TaskTemplate
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                Name = t.Name,
                Title = t.Name,
                Description = t.Description,
                TaskType = t.Type,
                Priority = t.Priority,
                EstimatedHours = t.Hours,
                DefaultSlaReminderHours = t.DueAfterHours is > 0 ? Math.Max(1, t.DueAfterHours.Value / 4) : 24,
                Checklist = TaskIndustryPacks.ChecklistJson(t),
                IndustryKey = pack.Key,
                StageKey = t.StageKey,
                ProgressMode = TaskProgressMode.Checklist,
                RecurrenceType = recurring ? t.Recurrence : TaskRecurrenceType.None,
                RecurrenceDays = t.RecurrenceDays,
                RecurrenceTime = t.RecurrenceTime,
                DueAfterHours = t.DueAfterHours,
                DefaultAssigneeIds = recurring && assignees.Count > 0 ? System.Text.Json.JsonSerializer.Serialize(assignees) : null,
                NextRunAt = recurring ? TaskV2Helper.NextRun(t.Recurrence, t.RecurrenceDays, t.RecurrenceTime, now) : null,
                IsActive = true,
                CreatedBy = CurrentUserEmail,
            });
            result.CreatedTemplates++;
            if (recurring) result.RecurringTemplates++;
        }
        await db.SaveChangesAsync();
        return Ok(AppResponse<InstallIndustryPackResultDto>.Success(result));
    }

    // ─── Hỗ trợ ──────────────────────────────────────────────────

    private async Task<string?> ValidateOwnerAsync(Guid? ownerId)
    {
        if (ownerId == null) return null;
        var ok = await db.Employees.AsNoTracking()
            .AnyAsync(e => e.Id == ownerId && e.StoreId == RequiredStoreId && e.Deleted == null);
        return ok ? null : "Người phụ trách không hợp lệ";
    }

    private async Task<List<TaskProjectDto>> WithStatsAsync(List<TaskProject> projects, bool withStageCounts)
    {
        var ids = projects.Select(p => p.Id).ToList();
        var now = DateTime.Now;
        var rows = await db.WorkTasks.AsNoTracking()
            .Where(t => t.ProjectId != null && ids.Contains(t.ProjectId.Value) && t.IsActive && t.Status != WorkTaskStatus.Cancelled)
            .Select(t => new { t.ProjectId, t.Status, t.Progress, t.DueDate, t.StageKey, t.EstimatedHours })
            .ToListAsync();
        var byProject = rows.GroupBy(r => r.ProjectId!.Value).ToDictionary(g => g.Key, g => g.ToList());
        return projects.Select(p =>
        {
            var tasks = byProject.GetValueOrDefault(p.Id) ?? new();
            // Tiến độ có trọng số theo giờ ước tính (việc không ước tính = 1 giờ).
            decimal wSum = 0, wDone = 0;
            foreach (var t in tasks)
            {
                var w = t.EstimatedHours is > 0 ? t.EstimatedHours.Value : 1m;
                wSum += w;
                wDone += w * (t.Status == WorkTaskStatus.Completed ? 100 : Math.Clamp(t.Progress, 0, 100)) / 100m;
            }
            return new TaskProjectDto
            {
                Id = p.Id,
                Code = p.Code,
                Name = p.Name,
                Description = p.Description,
                IndustryKey = p.IndustryKey,
                Color = p.Color,
                Status = p.Status,
                OwnerEmployeeId = p.OwnerEmployeeId,
                OwnerName = p.OwnerEmployee != null ? $"{p.OwnerEmployee.LastName} {p.OwnerEmployee.FirstName}".Trim() : null,
                BranchId = p.BranchId,
                CustomerName = p.CustomerName,
                CustomerPhone = p.CustomerPhone,
                Address = p.Address,
                Budget = p.Budget,
                StartDate = p.StartDate,
                DueDate = p.DueDate,
                CompletedAt = p.CompletedAt,
                Stages = TaskV2Helper.ParseStages(p.Stages).Select(ToDto).ToList(),
                CreatedAt = p.CreatedAt,
                TaskCount = tasks.Count,
                DoneCount = tasks.Count(t => t.Status == WorkTaskStatus.Completed),
                InProgressCount = tasks.Count(t => t.Status == WorkTaskStatus.InProgress),
                OverdueCount = tasks.Count(t => t.Status != WorkTaskStatus.Completed && t.DueDate < now),
                Progress = wSum == 0 ? 0 : (int)Math.Round(wDone * 100 / wSum),
                IsOverdue = p.Status == TaskProjectStatus.Active && p.DueDate < now,
                StageCounts = withStageCounts
                    ? tasks.Where(t => t.StageKey != null).GroupBy(t => t.StageKey!).ToDictionary(g => g.Key, g => g.Count())
                    : null,
            };
        }).ToList();
    }
}

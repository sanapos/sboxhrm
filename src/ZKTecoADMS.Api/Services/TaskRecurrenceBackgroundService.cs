using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Services;

namespace ZKTecoADMS.Api.Services;

/// <summary>Tạo việc từ mẫu lặp lại — dùng chung cho dịch vụ nền và nút «Tạo ngay».</summary>
public static class TaskRecurrenceRunner
{
    /// <summary>
    /// Mỗi nhân viên nhận một việc riêng (checklist riêng, tiến độ riêng).
    /// Không lưu — người gọi SaveChanges. Trả về số việc tạo.
    /// </summary>
    public static async Task<int> CreateTasksFromTemplateAsync(
        ZKTecoDbContext db,
        TaskTemplate template,
        DateTime runAt,
        Guid assignedById,
        ISystemNotificationService? notifications,
        CancellationToken ct = default)
    {
        var assignees = TaskV2Helper.ParseGuidList(template.DefaultAssigneeIds);
        if (assignees.Count == 0) return 0;
        var valid = await db.Employees.AsNoTracking()
            .Where(e => assignees.Contains(e.Id) && e.StoreId == template.StoreId && e.Deleted == null)
            .Select(e => new { e.Id, e.ApplicationUserId })
            .ToListAsync(ct);
        if (valid.Count == 0) return 0;

        // Dự án của mẫu phải còn hoạt động; giai đoạn phải thuộc quy trình dự án.
        Guid? projectId = null;
        string? stageKey = null;
        if (template.ProjectId.HasValue)
        {
            var project = await db.TaskProjects.AsNoTracking()
                .FirstOrDefaultAsync(p => p.Id == template.ProjectId && p.StoreId == template.StoreId &&
                                          p.Status == TaskProjectStatus.Active, ct);
            if (project != null)
            {
                projectId = project.Id;
                var stages = TaskV2Helper.ParseStages(project.Stages);
                stageKey = stages.FirstOrDefault(s => s.Key == template.StageKey)?.Key ?? stages.FirstOrDefault()?.Key;
            }
        }

        var due = template.DueAfterHours is > 0 ? runAt.AddHours(template.DueAfterHours.Value) : runAt.Date.AddDays(1).AddMinutes(-1);
        var created = 0;
        foreach (var emp in valid)
        {
            var task = new WorkTask
            {
                Id = Guid.NewGuid(),
                TaskCode = await TaskWorkflowHelper.GenerateTaskCodeAsync(db, template.StoreId, created),
                Title = $"{template.Title} · {runAt:dd/MM}",
                Description = template.Description,
                TaskType = template.TaskType,
                Priority = template.Priority,
                Status = WorkTaskStatus.Todo,
                StoreId = template.StoreId,
                AssignedById = assignedById,
                AssigneeId = emp.Id,
                TemplateId = template.Id,
                StartDate = runAt,
                DueDate = due,
                EstimatedHours = template.EstimatedHours,
                Tags = template.Tags,
                Checklist = TaskV2Helper.NormalizeChecklist(template.Checklist),
                ProgressMode = template.ProgressMode,
                ProjectId = projectId,
                StageKey = stageKey,
                SlaReminderHours = template.DefaultSlaReminderHours ?? Math.Max(1, (template.DueAfterHours ?? 24) / 4),
                IsActive = true,
                CreatedBy = "Lặp tự động",
            };
            task.Progress = TaskV2Helper.AutoProgress(task) ?? 0;
            db.WorkTasks.Add(task);
            await TaskWorkflowHelper.SyncAssigneesAsync(db, task.Id, emp.Id, new List<Guid> { emp.Id });
            db.TaskHistories.Add(new TaskHistory
            {
                Id = Guid.NewGuid(),
                TaskId = task.Id,
                UserId = assignedById,
                ChangeType = "Created",
                NewValue = task.Title,
                Description = $"Tạo tự động từ mẫu lặp «{template.Name}»",
            });
            created++;

            if (notifications != null && emp.ApplicationUserId is Guid uid && uid != Guid.Empty)
            {
                try
                {
                    await notifications.CreateAndSendAsync(
                        uid, NotificationType.Info, "Việc định kỳ",
                        $"{task.Title} — hạn {due:HH:mm dd/MM}",
                        relatedEntityId: task.Id, relatedEntityType: "WorkTask",
                        categoryCode: "task", storeId: template.StoreId);
                }
                catch { /* thông báo lỗi không chặn tạo việc */ }
            }
        }
        template.LastRunAt = runAt;
        return created;
    }
}

/// <summary>
/// Mỗi 5 phút: (1) tạo việc từ mẫu lặp đến hạn; (2) nhắc SLA trước hạn chót; (3) báo việc quá hạn một lần.
/// Trước đây nhắc SLA chỉ chạy khi quản lý bấm nút.
/// </summary>
public class TaskRecurrenceBackgroundService(IServiceProvider sp, ILogger<TaskRecurrenceBackgroundService> logger)
    : BackgroundService
{
    private static readonly TimeSpan Interval = TimeSpan.FromMinutes(5);

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        await Task.Delay(TimeSpan.FromSeconds(45), stoppingToken);
        while (!stoppingToken.IsCancellationRequested)
        {
            try { await RunRecurrenceAsync(stoppingToken); }
            catch (Exception ex) { logger.LogError(ex, "Task recurrence run failed"); }
            try { await RunRemindersAsync(stoppingToken); }
            catch (Exception ex) { logger.LogError(ex, "Task SLA reminder run failed"); }
            await Task.Delay(Interval, stoppingToken);
        }
    }

    private async Task RunRecurrenceAsync(CancellationToken ct)
    {
        using var scope = sp.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<ZKTecoDbContext>();
        var notify = scope.ServiceProvider.GetService<ISystemNotificationService>();
        var now = DateTime.Now;
        var due = await db.TaskTemplates.IgnoreQueryFilters().AsTracking()
            .Where(t => t.IsActive && t.Deleted == null &&
                        t.RecurrenceType != TaskRecurrenceType.None &&
                        t.NextRunAt != null && t.NextRunAt <= now &&
                        t.DefaultAssigneeIds != null)
            .OrderBy(t => t.NextRunAt)
            .Take(50)
            .ToListAsync(ct);
        foreach (var template in due)
        {
            var runAt = template.NextRunAt!.Value;
            // Máy chủ tắt lâu: bỏ các lần đã lỡ quá 12 giờ, chỉ tạo lần gần nhất.
            if (now - runAt > TimeSpan.FromHours(12))
            {
                template.NextRunAt = TaskV2Helper.NextRun(template.RecurrenceType, template.RecurrenceDays, template.RecurrenceTime, now);
                await db.SaveChangesAsync(ct);
                continue;
            }
            var assignedBy = await db.Stores.IgnoreQueryFilters().AsNoTracking()
                .Where(s => s.Id == template.StoreId).Select(s => s.OwnerId).FirstOrDefaultAsync(ct)
                ?? await db.Users.AsNoTracking()
                    .Where(u => u.StoreId == template.StoreId)
                    .OrderBy(u => u.Role == "Admin" ? 0 : u.Role == "Manager" ? 1 : 2)
                    .Select(u => (Guid?)u.Id).FirstOrDefaultAsync(ct);
            template.NextRunAt = TaskV2Helper.NextRun(template.RecurrenceType, template.RecurrenceDays, template.RecurrenceTime, runAt);
            if (assignedBy == null)
            {
                await db.SaveChangesAsync(ct);
                continue;
            }
            try
            {
                var n = await TaskRecurrenceRunner.CreateTasksFromTemplateAsync(db, template, runAt, assignedBy.Value, notify, ct);
                await db.SaveChangesAsync(ct);
                logger.LogInformation("Recurring template {Id} created {N} tasks", template.Id, n);
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "Recurring template {Id} failed", template.Id);
                db.ChangeTracker.Clear();
                var fresh = await db.TaskTemplates.IgnoreQueryFilters().AsTracking().FirstAsync(t => t.Id == template.Id, ct);
                fresh.NextRunAt = template.NextRunAt;
                await db.SaveChangesAsync(ct);
            }
        }
    }

    /// <summary>Nhắc trước hạn (theo SlaReminderHours) và báo quá hạn — mỗi việc một lần/mốc (ghi dấu ở TaskHistory).</summary>
    private async Task RunRemindersAsync(CancellationToken ct)
    {
        using var scope = sp.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<ZKTecoDbContext>();
        var notify = scope.ServiceProvider.GetService<ISystemNotificationService>();
        if (notify == null) return;
        var now = DateTime.Now;
        var horizon = now.AddHours(72);
        var candidates = await db.WorkTasks.IgnoreQueryFilters().AsNoTracking()
            .Where(t => t.IsActive && t.Deleted == null && t.DueDate != null && t.AssigneeId != null &&
                        t.DueDate < horizon && t.DueDate > now.AddDays(-2) &&
                        t.Status != WorkTaskStatus.Completed && t.Status != WorkTaskStatus.Cancelled)
            .Select(t => new { t.Id, t.Title, t.DueDate, t.SlaReminderHours, t.AssigneeId, t.AssignedById, t.StoreId })
            .Take(500)
            .ToListAsync(ct);
        if (candidates.Count == 0) return;
        var ids = candidates.Select(c => c.Id).ToList();
        var marks = await db.TaskHistories.AsNoTracking()
            .Where(h => ids.Contains(h.TaskId) && (h.ChangeType == "SlaReminded" || h.ChangeType == "OverdueAlerted"))
            .Select(h => new { h.TaskId, h.ChangeType })
            .ToListAsync(ct);
        var done = marks.Select(m => (m.TaskId, m.ChangeType)).ToHashSet();

        foreach (var t in candidates)
        {
            var overdue = t.DueDate < now;
            var kind = overdue ? "OverdueAlerted" : "SlaReminded";
            if (!overdue && now < t.DueDate!.Value.AddHours(-(t.SlaReminderHours ?? 24))) continue;
            if (done.Contains((t.Id, kind))) continue;
            var userId = await db.Employees.IgnoreQueryFilters().AsNoTracking()
                .Where(e => e.Id == t.AssigneeId).Select(e => e.ApplicationUserId).FirstOrDefaultAsync(ct);
            try
            {
                if (userId is Guid uid && uid != Guid.Empty)
                    await notify.CreateAndSendAsync(
                        uid, overdue ? NotificationType.Warning : NotificationType.Reminder,
                        overdue ? "Công việc quá hạn" : "Sắp đến hạn công việc",
                        overdue
                            ? $"\"{t.Title}\" đã quá hạn ({t.DueDate:HH:mm dd/MM})"
                            : $"\"{t.Title}\" đến hạn lúc {t.DueDate:HH:mm dd/MM}",
                        relatedEntityId: t.Id, relatedEntityType: "WorkTask", categoryCode: "task", storeId: t.StoreId);
                if (overdue && t.AssignedById != Guid.Empty && t.AssignedById != userId)
                    await notify.CreateAndSendAsync(
                        t.AssignedById, NotificationType.Warning, "Việc giao đã quá hạn",
                        $"\"{t.Title}\" chưa hoàn thành, quá hạn {t.DueDate:HH:mm dd/MM}",
                        relatedEntityId: t.Id, relatedEntityType: "WorkTask", categoryCode: "task", storeId: t.StoreId);
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex, "Task reminder notify failed {Id}", t.Id);
            }
            db.TaskHistories.Add(new TaskHistory
            {
                Id = Guid.NewGuid(),
                TaskId = t.Id,
                UserId = t.AssignedById,
                ChangeType = kind,
                Description = overdue ? "Tự động báo quá hạn" : "Tự động nhắc trước hạn",
            });
        }
        await db.SaveChangesAsync(ct);
    }
}

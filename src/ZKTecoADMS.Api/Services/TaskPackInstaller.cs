using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Services;

namespace ZKTecoADMS.Api.Services;

/// <summary>Cài mẫu việc của một gói ngành vào cửa hàng (bỏ qua mẫu trùng tên đã cài).</summary>
public static class TaskPackInstaller
{
    public sealed record Result(int Created, int Skipped, int Recurring);

    /// <summary>
    /// Việc định kỳ chạy khi có người nhận: danh sách cố định (<paramref name="assignees"/>)
    /// hoặc người có ca hôm đó (mẫu AssignOnShift). Không truyền người nhận → mẫu ca vẫn chạy.
    /// </summary>
    public static async Task<(Result? Result, string? Error)> InstallAsync(
        ZKTecoDbContext db, Guid storeId, TaskIndustryPack pack, bool enableRecurring,
        List<Guid>? assignees, string? by, CancellationToken ct = default)
    {
        var list = assignees?.Where(g => g != Guid.Empty).Distinct().ToList() ?? [];
        if (list.Count > 0)
        {
            var valid = await db.Employees.AsNoTracking()
                .CountAsync(e => list.Contains(e.Id) && e.StoreId == storeId && e.Deleted == null, ct);
            if (valid != list.Count) return (null, "Nhân viên nhận việc không hợp lệ");
        }
        var existing = await db.TaskTemplates.AsNoTracking()
            .Where(t => t.StoreId == storeId && t.IsActive && t.IndustryKey == pack.Key)
            .Select(t => t.Name).ToListAsync(ct);
        int created = 0, skipped = 0, recurringCount = 0;
        var now = DateTime.Now;
        foreach (var t in pack.Templates)
        {
            if (existing.Contains(t.Name))
            {
                skipped++;
                continue;
            }
            var recurring = enableRecurring && t.Recurrence != TaskRecurrenceType.None && (t.AssignOnShift || list.Count > 0);
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
                FormSchema = TaskIndustryPacks.FormJson(t),
                PieceRate = t.PieceRate,
                AssignOnShift = t.AssignOnShift,
                RequireCheckIn = t.RequireCheckIn,
                IndustryKey = pack.Key,
                StageKey = t.StageKey,
                ProgressMode = TaskProgressMode.Checklist,
                RecurrenceType = recurring ? t.Recurrence : TaskRecurrenceType.None,
                RecurrenceDays = t.RecurrenceDays,
                RecurrenceTime = t.RecurrenceTime,
                DueAfterHours = t.DueAfterHours,
                DefaultAssigneeIds = recurring && list.Count > 0 ? System.Text.Json.JsonSerializer.Serialize(list) : null,
                NextRunAt = recurring ? TaskV2Helper.NextRun(t.Recurrence, t.RecurrenceDays, t.RecurrenceTime, now) : null,
                IsActive = true,
                CreatedBy = by,
            });
            created++;
            if (recurring) recurringCount++;
        }
        await db.SaveChangesAsync(ct);
        return (new Result(created, skipped, recurringCount), null);
    }
}

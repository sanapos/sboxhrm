using System.Security.Claims;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Infrastructure.Services;

/// <summary>Shared task assignment / authorization helpers.</summary>
public static class TaskWorkflowHelper
{
    public static bool IsManagerOrAdmin(ClaimsPrincipal user) =>
        user.IsInRole("Admin") ||
        user.IsInRole("Manager") ||
        user.IsInRole("StoreOwner") ||
        user.IsInRole("SuperAdmin");

    public static async Task<Employee?> GetEmployeeForUserAsync(
        ZKTecoDbContext db, Guid storeId, Guid userId) =>
        await db.Employees
            .AsNoTracking()
            .FirstOrDefaultAsync(e =>
                e.ApplicationUserId == userId && e.StoreId == storeId && e.Deleted == null);

    public static async Task<bool> IsTaskParticipantAsync(
        ZKTecoDbContext db, WorkTask task, Guid employeeId)
    {
        if (task.AssigneeId == employeeId) return true;
        return await db.TaskAssignees
            .AnyAsync(ta => ta.TaskId == task.Id && ta.EmployeeId == employeeId);
    }

    public static async Task<bool> CanModifyTaskAsync(
        ZKTecoDbContext db,
        WorkTask task,
        Guid currentUserId,
        Guid storeId,
        ClaimsPrincipal user)
    {
        if (IsManagerOrAdmin(user)) return true;
        if (task.AssignedById == currentUserId) return true;

        var employee = await GetEmployeeForUserAsync(db, storeId, currentUserId);
        if (employee == null) return false;
        return await IsTaskParticipantAsync(db, task, employee.Id);
    }

    public static Task<bool> CanViewTaskAsync(
        ZKTecoDbContext db,
        WorkTask task,
        Guid currentUserId,
        Guid storeId,
        ClaimsPrincipal user) =>
        CanModifyTaskAsync(db, task, currentUserId, storeId, user);

    public static IQueryable<WorkTask> ApplyEmployeeVisibilityFilter(
        IQueryable<WorkTask> query,
        Guid? employeeId,
        Guid currentUserId) =>
        employeeId.HasValue
            ? query.Where(t =>
                t.AssignedById == currentUserId ||
                t.AssigneeId == employeeId.Value ||
                t.TaskAssignees!.Any(ta => ta.EmployeeId == employeeId.Value))
            : query.Where(t => t.AssignedById == currentUserId);

    public static async Task<IQueryable<WorkTask>> ApplyViewerScopeAsync(
        IQueryable<WorkTask> query,
        ZKTecoDbContext db,
        Guid storeId,
        Guid currentUserId,
        ClaimsPrincipal user)
    {
        if (IsManagerOrAdmin(user)) return query;

        var emp = await GetEmployeeForUserAsync(db, storeId, currentUserId);
        if (emp == null)
            return query.Where(_ => false);

        return ApplyEmployeeVisibilityFilter(query, emp.Id, currentUserId);
    }

    /// <summary>
    /// Keeps TaskAssignees in sync with primary assignee + optional co-assignees.
    /// </summary>
    public static async Task SyncAssigneesAsync(
        ZKTecoDbContext db,
        Guid taskId,
        Guid? primaryAssigneeId,
        IEnumerable<Guid>? assigneeIds,
        bool replaceAll = true)
    {
        var targetIds = new HashSet<Guid>();
        if (primaryAssigneeId.HasValue) targetIds.Add(primaryAssigneeId.Value);
        if (assigneeIds != null)
        {
            foreach (var id in assigneeIds.Where(id => id != Guid.Empty))
                targetIds.Add(id);
        }

        if (!replaceAll && targetIds.Count == 0) return;

        var existing = await db.TaskAssignees
            .Where(ta => ta.TaskId == taskId)
            .ToListAsync();

        if (targetIds.Count == 0)
        {
            db.TaskAssignees.RemoveRange(existing);
            return;
        }

        var existingIds = existing.Select(e => e.EmployeeId).ToHashSet();
        foreach (var row in existing.Where(e => !targetIds.Contains(e.EmployeeId)))
            db.TaskAssignees.Remove(row);

        foreach (var empId in targetIds.Where(id => !existingIds.Contains(id)))
        {
            db.TaskAssignees.Add(new TaskAssignee
            {
                Id = Guid.NewGuid(),
                TaskId = taskId,
                EmployeeId = empId,
                Role = primaryAssigneeId == empId ? "Chính" : "Phụ",
                AssignedAt = DateTime.Now
            });
        }

        foreach (var row in existing.Where(e => targetIds.Contains(e.EmployeeId)))
        {
            row.Role = primaryAssigneeId == row.EmployeeId ? "Chính" : "Phụ";
        }
    }

    public static async Task<string> GenerateTaskCodeAsync(ZKTecoDbContext db, Guid storeId)
    {
        var today = DateTime.UtcNow.ToString("yyyyMMdd");
        var prefix = $"TASK-{today}-";
        var countToday = await db.WorkTasks
            .CountAsync(t => t.StoreId == storeId && t.TaskCode.StartsWith(prefix));
        return $"{prefix}{(countToday + 1):D4}";
    }

    public static IQueryable<WorkTask> ApplyBranchFilter(
        IQueryable<WorkTask> query,
        BranchQueryHelper.BranchEmployeeScope? branchScope)
    {
        if (branchScope == null || branchScope.IsEmpty) return query;
        return query.Where(t =>
            (t.AssigneeId != null && branchScope.EmployeeIds.Contains(t.AssigneeId.Value)) ||
            (t.TaskAssignees != null && t.TaskAssignees.Any(ta =>
                branchScope.EmployeeIds.Contains(ta.EmployeeId))));
    }
}

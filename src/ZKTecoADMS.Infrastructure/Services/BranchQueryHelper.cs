using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Services;

/// <summary>Resolve branch trees and apply employee filters by branch.</summary>
public static class BranchQueryHelper
{
    public static async Task<HashSet<Guid>> GetBranchIdsIncludingChildrenAsync(
        ZKTecoDbContext db,
        Guid storeId,
        Guid rootBranchId,
        bool includeChildren = true)
    {
        var result = new HashSet<Guid> { rootBranchId };
        if (!includeChildren) return result;

        var exists = await db.Branches.AnyAsync(b =>
            b.Id == rootBranchId && b.StoreId == storeId && b.Deleted == null);
        if (!exists) return result;

        var childrenByParent = await db.Branches
            .Where(b => b.StoreId == storeId && b.Deleted == null && b.ParentBranchId != null)
            .Select(b => new { b.Id, ParentId = b.ParentBranchId!.Value })
            .ToListAsync();

        var lookup = childrenByParent
            .GroupBy(p => p.ParentId)
            .ToDictionary(g => g.Key, g => g.Select(x => x.Id).ToList());

        var queue = new Queue<Guid>();
        if (lookup.TryGetValue(rootBranchId, out var direct))
        {
            foreach (var c in direct) queue.Enqueue(c);
        }

        while (queue.Count > 0)
        {
            var current = queue.Dequeue();
            if (!result.Add(current)) continue;
            if (lookup.TryGetValue(current, out var children))
            {
                foreach (var c in children) queue.Enqueue(c);
            }
        }

        return result;
    }

    public static IQueryable<Employee> FilterByBranchIds(
        IQueryable<Employee> query,
        HashSet<Guid>? branchIds)
    {
        if (branchIds == null || branchIds.Count == 0) return query;
        return query.Where(e => e.BranchId.HasValue && branchIds.Contains(e.BranchId.Value));
    }

    public static async Task<IQueryable<Employee>> ApplyBranchFilterAsync(
        IQueryable<Employee> query,
        ZKTecoDbContext db,
        Guid storeId,
        Guid? branchId,
        bool includeChildBranches = true)
    {
        if (!branchId.HasValue) return query;
        var ids = await GetBranchIdsIncludingChildrenAsync(db, storeId, branchId.Value, includeChildBranches);
        return FilterByBranchIds(query, ids);
    }

    /// <summary>Employee + application-user ids for branch-scoped dashboard stats.</summary>
    public sealed class BranchEmployeeScope
    {
        public HashSet<Guid> EmployeeIds { get; init; } = new();
        public HashSet<Guid> ApplicationUserIds { get; init; } = new();
        public bool IsEmpty => EmployeeIds.Count == 0;
    }

    public static async Task<BranchEmployeeScope?> ResolveEmployeeScopeAsync(
        ZKTecoDbContext db,
        Guid storeId,
        Guid? branchId,
        bool includeChildBranches = true)
    {
        if (!branchId.HasValue) return null;

        var query = db.Employees.Where(e => e.StoreId == storeId && e.Deleted == null);
        query = await ApplyBranchFilterAsync(query, db, storeId, branchId, includeChildBranches);
        var rows = await query
            .Select(e => new { e.Id, e.ApplicationUserId })
            .ToListAsync();

        return new BranchEmployeeScope
        {
            EmployeeIds = rows.Select(r => r.Id).ToHashSet(),
            ApplicationUserIds = rows
                .Where(r => r.ApplicationUserId.HasValue)
                .Select(r => r.ApplicationUserId!.Value)
                .ToHashSet()
        };
    }
}

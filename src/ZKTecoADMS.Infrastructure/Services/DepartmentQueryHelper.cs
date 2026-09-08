using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Infrastructure.Services;

/// <summary>Resolve department trees and apply employee filters by department (incl. children).</summary>
public static class DepartmentQueryHelper
{
    public static async Task<HashSet<Guid>> GetDepartmentIdsIncludingChildrenAsync(
        ZKTecoDbContext db,
        Guid storeId,
        Guid rootDepartmentId,
        bool includeChildren = true)
    {
        var result = new HashSet<Guid> { rootDepartmentId };
        if (!includeChildren) return result;

        var exists = await db.Departments.AnyAsync(d =>
            d.Id == rootDepartmentId && d.StoreId == storeId && d.Deleted == null);
        if (!exists) return result;

        var childrenByParent = await db.Departments
            .Where(d => d.StoreId == storeId && d.Deleted == null && d.ParentDepartmentId != null)
            .Select(d => new { d.Id, ParentId = d.ParentDepartmentId!.Value })
            .ToListAsync();

        var lookup = childrenByParent
            .GroupBy(p => p.ParentId)
            .ToDictionary(g => g.Key, g => g.Select(x => x.Id).ToList());

        var queue = new Queue<Guid>();
        if (lookup.TryGetValue(rootDepartmentId, out var direct))
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

    public static async Task<HashSet<Guid>> ResolveDepartmentIdsAsync(
        ZKTecoDbContext db,
        Guid storeId,
        Guid? departmentId,
        string? departmentName,
        bool includeChildren = true)
    {
        var ids = new HashSet<Guid>();
        if (departmentId is { } id && id != Guid.Empty)
        {
            ids.UnionWith(await GetDepartmentIdsIncludingChildrenAsync(
                db, storeId, id, includeChildren));
            return ids;
        }

        if (string.IsNullOrWhiteSpace(departmentName)) return ids;

        var matches = await db.Departments
            .Where(d => d.StoreId == storeId && d.Deleted == null && d.Name == departmentName)
            .Select(d => d.Id)
            .ToListAsync();

        foreach (var matchId in matches)
        {
            ids.UnionWith(await GetDepartmentIdsIncludingChildrenAsync(
                db, storeId, matchId, includeChildren));
        }

        return ids;
    }

    public static async Task<IQueryable<Employee>> ApplyDepartmentFilterAsync(
        IQueryable<Employee> query,
        ZKTecoDbContext db,
        Guid storeId,
        Guid? departmentId,
        string? departmentName,
        bool includeChildDepartments = true)
    {
        if (!departmentId.HasValue && string.IsNullOrWhiteSpace(departmentName))
            return query;

        var ids = await ResolveDepartmentIdsAsync(
            db, storeId, departmentId, departmentName, includeChildDepartments);

        if (ids.Count == 0)
        {
            // Legacy rows may only have Department name, no Department entity match.
            if (!string.IsNullOrWhiteSpace(departmentName))
                return query.Where(e => e.Department == departmentName);
            return query;
        }

        var idList = ids.ToList();
        var nameList = await db.Departments
            .Where(d => idList.Contains(d.Id))
            .Select(d => d.Name)
            .ToListAsync();

        return query.Where(e =>
            (e.DepartmentId.HasValue && idList.Contains(e.DepartmentId.Value))
            || (e.Department != null && nameList.Contains(e.Department)));
    }
}

using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Helpers;

/// <summary>Cây phòng ban: kiểm vòng lặp, tính lại cấp / đường dẫn, chuyển nhân viên (đồng bộ tên chữ).</summary>
public static class DepartmentOrgHelper
{
    /// <summary>Đặt [parentId] làm cha của [id] có tạo vòng lặp không.</summary>
    public static bool CreatesCycle(IReadOnlyDictionary<Guid, Guid?> parentOf, Guid id, Guid? parentId)
    {
        var cur = parentId;
        var guard = 0;
        while (cur is Guid c && guard++ < 10_000)
        {
            if (c == id) return true;
            cur = parentOf.GetValueOrDefault(c);
        }
        return false;
    }

    /// <summary>Tính lại Level và HierarchyPath ("/cha/ông/…/") cho toàn bộ phòng ban (đã tracking).</summary>
    public static void RecomputeHierarchy(IReadOnlyList<Department> all)
    {
        var byId = all.ToDictionary(d => d.Id);
        var children = all.Where(d => d.ParentDepartmentId != null && byId.ContainsKey(d.ParentDepartmentId.Value))
            .GroupBy(d => d.ParentDepartmentId!.Value)
            .ToDictionary(g => g.Key, g => g.ToList());
        var roots = all.Where(d => d.ParentDepartmentId == null || !byId.ContainsKey(d.ParentDepartmentId.Value)).ToList();
        var queue = new Queue<(Department d, int level, string path)>(roots.Select(r => (r, 0, "/")));
        var seen = new HashSet<Guid>();
        while (queue.Count > 0)
        {
            var (d, level, path) = queue.Dequeue();
            if (!seen.Add(d.Id)) continue;
            if (d.Level != level || d.HierarchyPath != path)
            {
                d.Level = level;
                d.HierarchyPath = path;
            }
            foreach (var c in children.GetValueOrDefault(d.Id) ?? [])
                queue.Enqueue((c, level + 1, $"{path}{d.Id}/"));
        }
    }

    /// <summary>Id phòng ban và mọi phòng con.</summary>
    public static HashSet<Guid> WithDescendants(IEnumerable<(Guid id, Guid? parent)> all, Guid root)
    {
        var kids = all.Where(x => x.parent != null).GroupBy(x => x.parent!.Value).ToDictionary(g => g.Key, g => g.Select(x => x.id).ToList());
        var set = new HashSet<Guid> { root };
        var q = new Queue<Guid>([root]);
        while (q.Count > 0)
            foreach (var c in kids.GetValueOrDefault(q.Dequeue()) ?? [])
                if (set.Add(c)) q.Enqueue(c);
        return set;
    }

    /// <summary>Chuyển nhân viên sang phòng ban (null = bỏ phòng ban); cập nhật cả tên chữ trên hồ sơ.</summary>
    public static async Task<int> MoveEmployeesAsync(ZKTecoDbContext db, Guid storeId, IReadOnlyCollection<Guid> employeeIds,
        Guid? targetDepartmentId, CancellationToken ct = default)
    {
        string? targetName = null;
        if (targetDepartmentId is Guid t)
        {
            targetName = await db.Departments.AsNoTracking().Where(d => d.Id == t && d.StoreId == storeId)
                .Select(d => d.Name).FirstOrDefaultAsync(ct);
            if (targetName == null) return -1;
        }
        var emps = await db.Employees.AsTracking()
            .Where(e => e.StoreId == storeId && employeeIds.Contains(e.Id))
            .ToListAsync(ct);
        foreach (var e in emps)
        {
            e.DepartmentId = targetDepartmentId;
            e.Department = targetName;
        }
        await db.SaveChangesAsync(ct);
        return emps.Count;
    }
}

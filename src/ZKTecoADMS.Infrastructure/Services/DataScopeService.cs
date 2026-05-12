using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.Interfaces;

namespace ZKTecoADMS.Infrastructure.Services;

/// <summary>
/// Resolve phạm vi dữ liệu theo phòng ban, chi nhánh + cấp quản lý.
/// Logic phân quyền:
/// 1. Phòng ban: Department.ManagerId + DepartmentPermission (CanView)
/// 2. Chi nhánh: Branch.ManagerId (là EmployeeId) + BranchPermission (CanView)
/// 3. Nhân viên: NV trong PB quản lý + NV trong CN quản lý + NV báo cáo trực tiếp
/// </summary>
public class DataScopeService(ZKTecoDbContext context) : IDataScopeService
{
    public async Task<List<Guid>> GetManagedDepartmentIdsAsync(Guid userId, Guid storeId)
    {
        var result = new HashSet<Guid>();

        // Tìm EmployeeId tương ứng với userId (Department.ManagerId là FK đến Employee)
        var employeeId = await context.Employees
            .Where(e => e.ApplicationUserId == userId && e.StoreId == storeId)
            .Select(e => e.Id)
            .FirstOrDefaultAsync();

        // 1. Phòng ban mà user là trưởng phòng (Department.ManagerId = EmployeeId)
        if (employeeId != Guid.Empty)
        {
            var managedDepts = await context.Departments
                .Where(d => d.ManagerId == employeeId && d.StoreId == storeId && d.Deleted == null)
                .Select(d => new { d.Id, d.HierarchyPath })
                .ToListAsync();

            foreach (var dept in managedDepts)
            {
                result.Add(dept.Id);
                // Tìm PB con bằng HierarchyPath (prefix = parentPath + deptId + "/")
                if (!string.IsNullOrEmpty(dept.HierarchyPath))
                {
                    var childPrefix = $"{dept.HierarchyPath}{dept.Id}/";
                    var childIds = await context.Departments
                        .Where(d => d.StoreId == storeId && d.Deleted == null &&
                                    d.HierarchyPath != null &&
                                    d.HierarchyPath.StartsWith(childPrefix))
                        .Select(d => d.Id)
                        .ToListAsync();
                    foreach (var childId in childIds)
                        result.Add(childId);
                }
            }
        }

        // 2. Phòng ban được phân quyền qua DepartmentPermission (CanView = true)
        var deptPermissions = await context.DepartmentPermissions
            .Include(dp => dp.Department)
            .Where(dp => dp.UserId == userId &&
                         (dp.StoreId == storeId || dp.StoreId == null) &&
                         dp.IsActive && dp.CanView)
            .Select(dp => new { dp.DepartmentId, dp.IncludeChildren, HierarchyPath = dp.Department != null ? dp.Department.HierarchyPath : null })
            .ToListAsync();

        foreach (var perm in deptPermissions)
        {
            if (perm.DepartmentId == null)
            {
                // null = tất cả phòng ban
                var allDeptIds = await context.Departments
                    .Where(d => d.StoreId == storeId && d.Deleted == null)
                    .Select(d => d.Id)
                    .ToListAsync();
                foreach (var id in allDeptIds) result.Add(id);
                break;
            }

            result.Add(perm.DepartmentId.Value);

            if (perm.IncludeChildren && !string.IsNullOrEmpty(perm.HierarchyPath) && perm.DepartmentId.HasValue)
            {
                var childPrefix = $"{perm.HierarchyPath}{perm.DepartmentId.Value}/";
                var childIds = await context.Departments
                    .Where(d => d.StoreId == storeId && d.Deleted == null &&
                                d.HierarchyPath != null &&
                                d.HierarchyPath.StartsWith(childPrefix))
                    .Select(d => d.Id)
                    .ToListAsync();
                foreach (var childId in childIds)
                    result.Add(childId);
            }
        }

        return result.ToList();
    }

    public async Task<List<Guid>> GetSubordinateEmployeeIdsAsync(Guid userId, Guid storeId)
    {
        var result = new HashSet<Guid>();

        // Tìm EmployeeId tương ứng với userId
        var currentEmployeeId = await context.Employees
            .Where(e => e.ApplicationUserId == userId && e.StoreId == storeId)
            .Select(e => e.Id)
            .FirstOrDefaultAsync();

        // 1. NV báo cáo trực tiếp + ĐỆ QUY xuống cây DirectManagerEmployeeId
        // (manager của manager → all sub-tree). Cũng include ApplicationUser.ManagerId == userId.
        var directReports = await context.Employees
            .Where(e => e.StoreId == storeId &&
                        (e.ManagerId == userId ||
                         (currentEmployeeId != Guid.Empty && e.DirectManagerEmployeeId == currentEmployeeId)))
            .Select(e => e.Id)
            .ToListAsync();
        foreach (var id in directReports) result.Add(id);

        // BFS xuống cây DirectManagerEmployeeId để thu cấp dưới của cấp dưới.
        if (directReports.Count > 0)
        {
            // Pre-load whole map (store-scoped) once → tránh N+1.
            var pairs = await context.Employees
                .Where(e => e.StoreId == storeId && e.DirectManagerEmployeeId != null)
                .Select(e => new { e.Id, ManagerId = e.DirectManagerEmployeeId!.Value })
                .ToListAsync();
            var childrenByManager = pairs
                .GroupBy(p => p.ManagerId)
                .ToDictionary(g => g.Key, g => g.Select(x => x.Id).ToList());

            var queue = new Queue<Guid>(directReports);
            while (queue.Count > 0)
            {
                var parent = queue.Dequeue();
                if (!childrenByManager.TryGetValue(parent, out var children)) continue;
                foreach (var child in children)
                    if (result.Add(child)) queue.Enqueue(child);
            }
        }

        // 2. NV thuộc phòng ban quản lý
        var managedDeptIds = await GetManagedDepartmentIdsAsync(userId, storeId);
        if (managedDeptIds.Count > 0)
        {
            var deptEmployees = await context.Employees
                .Where(e => e.StoreId == storeId && e.DepartmentId.HasValue &&
                            managedDeptIds.Contains(e.DepartmentId.Value))
                .Select(e => e.Id)
                .ToListAsync();
            foreach (var id in deptEmployees)
                result.Add(id);
        }

        // 3. NV thuộc chi nhánh quản lý
        var managedBranchIds = await GetManagedBranchIdsAsync(userId, storeId);
        if (managedBranchIds.Count > 0)
        {
            var branchEmployees = await context.Employees
                .Where(e => e.StoreId == storeId && e.BranchId.HasValue &&
                            managedBranchIds.Contains(e.BranchId.Value))
                .Select(e => e.Id)
                .ToListAsync();
            foreach (var id in branchEmployees)
                result.Add(id);
        }

        return result.ToList();
    }

    public async Task<List<Guid>> GetManagedBranchIdsAsync(Guid userId, Guid storeId)
    {
        var result = new HashSet<Guid>();

        // Tìm EmployeeId tương ứng (Branch.ManagerId là FK đến Employee)
        var employeeId = await context.Employees
            .Where(e => e.ApplicationUserId == userId && e.StoreId == storeId)
            .Select(e => e.Id)
            .FirstOrDefaultAsync();

        // 1. Chi nhánh mà user là manager (Branch.ManagerId == employeeId)
        if (employeeId != Guid.Empty)
        {
            var managedBranches = await context.Branches
                .Where(b => b.ManagerId == employeeId && b.StoreId == storeId && b.Deleted == null)
                .Select(b => new { b.Id, b.ParentBranchId })
                .ToListAsync();

            foreach (var branch in managedBranches)
            {
                result.Add(branch.Id);
                // Include all descendant branches (BFS)
                await AddChildBranchIdsAsync(branch.Id, storeId, result);
            }
        }

        // 2. Chi nhánh được phân quyền qua BranchPermission (CanView = true)
        var branchPermissions = await context.BranchPermissions
            .Where(bp => bp.UserId == userId &&
                         (bp.StoreId == storeId || bp.StoreId == null) &&
                         bp.IsActive && bp.CanView)
            .Select(bp => new { bp.BranchId, bp.IncludeChildren })
            .ToListAsync();

        foreach (var perm in branchPermissions)
        {
            if (perm.BranchId == null)
            {
                // null = tất cả chi nhánh trong store
                var allBranchIds = await context.Branches
                    .Where(b => b.StoreId == storeId && b.Deleted == null)
                    .Select(b => b.Id)
                    .ToListAsync();
                foreach (var id in allBranchIds) result.Add(id);
                break;
            }

            result.Add(perm.BranchId.Value);

            if (perm.IncludeChildren)
                await AddChildBranchIdsAsync(perm.BranchId.Value, storeId, result);
        }

        return result.ToList();
    }

    /// <summary>BFS: thêm tất cả chi nhánh con (và cháu) vào result set.</summary>
    private async Task AddChildBranchIdsAsync(Guid parentId, Guid storeId, HashSet<Guid> result)
    {
        var allPairs = await context.Branches
            .Where(b => b.StoreId == storeId && b.Deleted == null && b.ParentBranchId != null)
            .Select(b => new { b.Id, ParentId = b.ParentBranchId!.Value })
            .ToListAsync();

        var childrenByParent = allPairs
            .GroupBy(p => p.ParentId)
            .ToDictionary(g => g.Key, g => g.Select(x => x.Id).ToList());

        var queue = new Queue<Guid>();
        if (childrenByParent.TryGetValue(parentId, out var directChildren))
            foreach (var c in directChildren) queue.Enqueue(c);

        while (queue.Count > 0)
        {
            var current = queue.Dequeue();
            if (!result.Add(current)) continue;
            if (childrenByParent.TryGetValue(current, out var children))
                foreach (var c in children) queue.Enqueue(c);
        }
    }

    public async Task<List<Guid>> GetSubordinateUserIdsAsync(Guid userId, Guid storeId)
    {
        // Reuse the recursive employee resolution and map back to ApplicationUserId.
        var subordinateEmpIds = await GetSubordinateEmployeeIdsAsync(userId, storeId);
        var result = new HashSet<Guid>();

        // 1. Users báo cáo trực tiếp (ApplicationUser.ManagerId == userId) — không phải employee chain.
        var directUserIds = await context.Users
            .Where(u => u.ManagerId == userId && u.StoreId == storeId)
            .Select(u => u.Id)
            .ToListAsync();
        foreach (var id in directUserIds)
            result.Add(id);

        // 2. Map subordinate employees -> their ApplicationUserId.
        if (subordinateEmpIds.Count > 0)
        {
            var subUserIds = await context.Employees
                .Where(e => subordinateEmpIds.Contains(e.Id) && e.ApplicationUserId.HasValue)
                .Select(e => e.ApplicationUserId!.Value)
                .ToListAsync();
            foreach (var id in subUserIds) result.Add(id);
        }

        return result.ToList();
    }

    public async Task<bool> CanAccessEmployeeDataAsync(Guid userId, Guid employeeId, Guid storeId)
    {
        // Use the recursive subordinate set (handles multi-level DirectManager chain + dept tree).
        var subordinateIds = await GetSubordinateEmployeeIdsAsync(userId, storeId);
        return subordinateIds.Contains(employeeId);
    }
}

using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.Interfaces;

namespace ZKTecoADMS.Infrastructure.Services;

/// <summary>
/// Resolve phạm vi dữ liệu theo phòng ban + cấp quản lý.
/// Logic:
/// 1. Tìm phòng ban user là Department.ManagerId
/// 2. Tìm phòng ban user được phân quyền qua DepartmentPermission (CanView)
/// 3. Dùng HierarchyPath resolve phòng ban con (nếu IncludeChildren)
/// 4. Lấy tất cả Employee có DepartmentId thuộc danh sách hoặc ManagerId == userId (báo cáo trực tiếp)
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

        // 1. NV báo cáo trực tiếp (Employee.ManagerId == userId hoặc DirectManagerEmployeeId == employeeId)
        var directReports = await context.Employees
            .Where(e => e.StoreId == storeId &&
                        (e.ManagerId == userId ||
                         (currentEmployeeId != Guid.Empty && e.DirectManagerEmployeeId == currentEmployeeId)))
            .Select(e => e.Id)
            .ToListAsync();
        foreach (var id in directReports)
            result.Add(id);

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

        return result.ToList();
    }

    public async Task<List<Guid>> GetSubordinateUserIdsAsync(Guid userId, Guid storeId)
    {
        var result = new HashSet<Guid>();

        // 1. Users báo cáo trực tiếp (ApplicationUser.ManagerId == userId)
        var directUserIds = await context.Users
            .Where(u => u.ManagerId == userId && u.StoreId == storeId)
            .Select(u => u.Id)
            .ToListAsync();
        foreach (var id in directUserIds)
            result.Add(id);

        // 2. Users thuộc phòng ban quản lý (qua Employee.ApplicationUserId)
        var managedDeptIds = await GetManagedDepartmentIdsAsync(userId, storeId);
        if (managedDeptIds.Count > 0)
        {
            var deptUserIds = await context.Employees
                .Where(e => e.StoreId == storeId && e.DepartmentId.HasValue &&
                            managedDeptIds.Contains(e.DepartmentId.Value) &&
                            e.ApplicationUserId.HasValue)
                .Select(e => e.ApplicationUserId!.Value)
                .ToListAsync();
            foreach (var id in deptUserIds)
                result.Add(id);
        }

        return result.ToList();
    }

    public async Task<bool> CanAccessEmployeeDataAsync(Guid userId, Guid employeeId, Guid storeId)
    {
        // Tìm EmployeeId tương ứng với userId
        var currentEmployeeId = await context.Employees
            .Where(e => e.ApplicationUserId == userId && e.StoreId == storeId)
            .Select(e => e.Id)
            .FirstOrDefaultAsync();

        // Kiểm tra nhanh: NV báo cáo trực tiếp (ManagerId hoặc DirectManagerEmployeeId)?
        var isDirect = await context.Employees
            .AnyAsync(e => e.Id == employeeId &&
                           (e.ManagerId == userId ||
                            (currentEmployeeId != Guid.Empty && e.DirectManagerEmployeeId == currentEmployeeId)));
        if (isDirect) return true;

        // Kiểm tra: NV thuộc phòng ban quản lý?
        var employee = await context.Employees
            .Where(e => e.Id == employeeId && e.StoreId == storeId)
            .Select(e => new { e.DepartmentId })
            .FirstOrDefaultAsync();

        if (employee?.DepartmentId == null) return false;

        var managedDeptIds = await GetManagedDepartmentIdsAsync(userId, storeId);
        return managedDeptIds.Contains(employee.DepartmentId.Value);
    }
}

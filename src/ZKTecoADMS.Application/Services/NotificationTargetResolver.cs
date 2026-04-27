using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Application.Services;

/// <summary>
/// Default resolver: walks <see cref="Department.ParentDepartmentId"/> up the tree and collects
/// each level's <see cref="Department.ManagerId"/> ApplicationUserId, plus all Admin users in
/// the same store (SuperAdmin excluded - manages system, not individual stores).
/// </summary>
public class NotificationTargetResolver(
    IRepository<Employee> employeeRepository,
    IRepository<Department> departmentRepository,
    UserManager<ApplicationUser> userManager
) : INotificationTargetResolver
{
    public async Task<IReadOnlyCollection<Guid>> ResolveManagersAsync(
        Guid? employeeApplicationUserId,
        Guid? storeId,
        int hierarchyLevels = 2,
        CancellationToken cancellationToken = default)
    {
        var targets = new HashSet<Guid>();

        // Department-chain managers (only when we know which employee triggered the action).
        if (employeeApplicationUserId.HasValue && employeeApplicationUserId.Value != Guid.Empty)
        {
            var employee = await employeeRepository.GetSingleAsync(
                e => e.ApplicationUserId == employeeApplicationUserId);
            if (employee?.DepartmentId != null)
            {
                var map = await BuildDeptManagerMapAsync(storeId, cancellationToken);
                foreach (var mgrUserId in WalkHierarchy(map, employee.DepartmentId.Value, hierarchyLevels))
                {
                    if (mgrUserId != employeeApplicationUserId.Value)
                        targets.Add(mgrUserId);
                }
            }
        }

        // Store admins (always, when storeId is known).
        if (storeId.HasValue)
        {
            var adminIds = await userManager.Users
                .Where(u => u.IsActive && u.Role == "Admin" && u.StoreId == storeId.Value)
                .Select(u => u.Id)
                .ToListAsync(cancellationToken);
            foreach (var id in adminIds)
            {
                if (employeeApplicationUserId == null || id != employeeApplicationUserId.Value)
                    targets.Add(id);
            }
        }

        return targets;
    }

    public async Task<IReadOnlyCollection<Guid>> ResolveEmployeeAndManagersAsync(
        Guid employeeApplicationUserId,
        Guid? storeId,
        int hierarchyLevels = 2,
        CancellationToken cancellationToken = default)
    {
        var managers = await ResolveManagersAsync(
            employeeApplicationUserId, storeId, hierarchyLevels, cancellationToken);
        var combined = new HashSet<Guid>(managers);
        if (employeeApplicationUserId != Guid.Empty)
            combined.Add(employeeApplicationUserId);
        return combined;
    }

    private async Task<Dictionary<Guid, (Guid? ParentId, Guid? ManagerUserId)>> BuildDeptManagerMapAsync(
        Guid? storeId, CancellationToken ct)
    {
        var depts = await departmentRepository.GetAllAsync(
            d => !storeId.HasValue || d.StoreId == storeId, cancellationToken: ct);

        var managerEmployeeIds = depts
            .Where(d => d.ManagerId.HasValue && d.ManagerId.Value != Guid.Empty)
            .Select(d => d.ManagerId!.Value)
            .Distinct()
            .ToList();

        var managerEmpToUserId = new Dictionary<Guid, Guid>();
        if (managerEmployeeIds.Count > 0)
        {
            var managers = await employeeRepository.GetAllAsync(
                e => managerEmployeeIds.Contains(e.Id), cancellationToken: ct);
            foreach (var m in managers)
            {
                if (m.ApplicationUserId.HasValue && m.ApplicationUserId.Value != Guid.Empty)
                    managerEmpToUserId[m.Id] = m.ApplicationUserId.Value;
            }
        }

        var map = new Dictionary<Guid, (Guid? ParentId, Guid? ManagerUserId)>();
        foreach (var d in depts)
        {
            Guid? mgrUserId = null;
            if (d.ManagerId.HasValue && managerEmpToUserId.TryGetValue(d.ManagerId.Value, out var uid))
                mgrUserId = uid;
            map[d.Id] = (d.ParentDepartmentId, mgrUserId);
        }
        return map;
    }

    /// <summary>
    /// Walk the department hierarchy up to <paramref name="levels"/> parents (inclusive of the
    /// starting department), yielding each level's manager ApplicationUserId. Cycle-safe.
    /// </summary>
    private static IEnumerable<Guid> WalkHierarchy(
        Dictionary<Guid, (Guid? ParentId, Guid? ManagerUserId)> map,
        Guid startDeptId,
        int levels)
    {
        var visited = new HashSet<Guid>();
        var currentId = (Guid?)startDeptId;
        for (int i = 0; i <= levels && currentId.HasValue; i++)
        {
            if (!visited.Add(currentId.Value)) yield break;
            if (!map.TryGetValue(currentId.Value, out var entry)) yield break;
            if (entry.ManagerUserId.HasValue) yield return entry.ManagerUserId.Value;
            currentId = entry.ParentId;
        }
    }
}

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

        // Department-chain managers + DirectManagerEmployeeId chain (only when we know which employee triggered the action).
        if (employeeApplicationUserId.HasValue && employeeApplicationUserId.Value != Guid.Empty)
        {
            var employee = await employeeRepository.GetSingleAsync(
                e => e.ApplicationUserId == employeeApplicationUserId);

            if (employee != null)
            {
                // (a) Walk up Department.ParentDepartmentId — pick each level's dept manager UserId.
                if (employee.DepartmentId != null)
                {
                    var deptMap = await BuildDeptManagerMapAsync(storeId, cancellationToken);
                    foreach (var mgrUserId in WalkDeptHierarchy(deptMap, employee.DepartmentId.Value, hierarchyLevels))
                    {
                        if (mgrUserId != employeeApplicationUserId.Value)
                            targets.Add(mgrUserId);
                    }
                }

                // (b) Walk up Employee.DirectManagerEmployeeId chain — even if dept tree breaks
                // (e.g. an upper manager isn't a department manager). Resolves Employee.Id -> ApplicationUserId.
                var empMap = await BuildEmployeeManagerMapAsync(storeId, cancellationToken);
                foreach (var mgrUserId in WalkEmployeeManagerChain(empMap, employee.Id, hierarchyLevels))
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
    private static IEnumerable<Guid> WalkDeptHierarchy(
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

    /// <summary>
    /// Build map: Employee.Id -> (DirectManagerEmployeeId, ApplicationUserId of THIS employee).
    /// Used to walk the explicit reporting chain (Employee.DirectManagerEmployeeId), which often
    /// holds the org structure when departments are flat.
    /// </summary>
    private async Task<Dictionary<Guid, (Guid? DirectManagerId, Guid? AppUserId)>> BuildEmployeeManagerMapAsync(
        Guid? storeId, CancellationToken ct)
    {
        var employees = await employeeRepository.GetAllAsync(
            e => !storeId.HasValue || e.StoreId == storeId, cancellationToken: ct);
        var map = new Dictionary<Guid, (Guid? DirectManagerId, Guid? AppUserId)>();
        foreach (var e in employees)
            map[e.Id] = (e.DirectManagerEmployeeId, e.ApplicationUserId);
        return map;
    }

    /// <summary>
    /// Walk Employee.DirectManagerEmployeeId UP from <paramref name="startEmployeeId"/>'s manager
    /// up to <paramref name="levels"/> hops, yielding ApplicationUserId of each manager (skip
    /// employees without an account). Cycle-safe. Does NOT yield the starting employee themselves.
    /// </summary>
    private static IEnumerable<Guid> WalkEmployeeManagerChain(
        Dictionary<Guid, (Guid? DirectManagerId, Guid? AppUserId)> map,
        Guid startEmployeeId,
        int levels)
    {
        var visited = new HashSet<Guid> { startEmployeeId };
        if (!map.TryGetValue(startEmployeeId, out var start)) yield break;
        var currentId = start.DirectManagerId;
        for (int i = 0; i < levels + 1 && currentId.HasValue && currentId.Value != Guid.Empty; i++)
        {
            if (!visited.Add(currentId.Value)) yield break;
            if (!map.TryGetValue(currentId.Value, out var entry)) yield break;
            if (entry.AppUserId.HasValue && entry.AppUserId.Value != Guid.Empty)
                yield return entry.AppUserId.Value;
            currentId = entry.DirectManagerId;
        }
    }
}

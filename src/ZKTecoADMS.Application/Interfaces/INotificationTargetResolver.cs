namespace ZKTecoADMS.Application.Interfaces;

/// <summary>
/// Resolves notification recipients per the organisation chart (Sơ đồ tổ chức phòng ban):
/// the employee's department manager + up to N parent-department managers + admins of the store.
/// SuperAdmin is excluded (system-wide role, not store-scoped).
/// </summary>
public interface INotificationTargetResolver
{
    /// <summary>
    /// Returns: department managers (2 levels of hierarchy by default) + admins in the store.
    /// Excludes the employee themselves.
    /// </summary>
    /// <param name="employeeApplicationUserId">ApplicationUser.Id of the employee whose chain to resolve. May be null when only admins are wanted.</param>
    /// <param name="storeId">Store scope. Required to include admins.</param>
    /// <param name="hierarchyLevels">How many parent departments to walk up. 0 = only the employee's own dept manager.</param>
    Task<IReadOnlyCollection<Guid>> ResolveManagersAsync(
        Guid? employeeApplicationUserId,
        Guid? storeId,
        int hierarchyLevels = 2,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// Same as <see cref="ResolveManagersAsync"/> but also includes the employee themselves.
    /// </summary>
    Task<IReadOnlyCollection<Guid>> ResolveEmployeeAndManagersAsync(
        Guid employeeApplicationUserId,
        Guid? storeId,
        int hierarchyLevels = 2,
        CancellationToken cancellationToken = default);
}

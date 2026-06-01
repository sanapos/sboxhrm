using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Application.Helpers;

/// <summary>
/// Resolves the target employee for an attendance correction from HR code and/or device PIN.
/// </summary>
public static class AttendanceCorrectionEmployeeResolver
{
    /// <summary>
    /// Resolves ApplicationUser id for FK + Employee profile.
    /// When the employee has no app account, returns <paramref name="actingUserId"/> for FK
    /// (the requester, e.g. Admin) while still returning the <see cref="Employee"/> row.
    /// </summary>
    public static async Task<(Guid? UserId, Employee? Employee, string? Error)> ResolveAsync(
        IRepository<Employee> employeeRepository,
        IRepository<DeviceUser> deviceUserRepository,
        Guid storeId,
        Guid actingUserId,
        string? employeeCode,
        string? pin,
        CancellationToken cancellationToken = default)
    {
        var employee = await FindEmployeeAsync(
            employeeRepository, deviceUserRepository, storeId, employeeCode, pin, cancellationToken);

        if (employee != null)
        {
            if (employee.ApplicationUserId.HasValue)
                return (employee.ApplicationUserId.Value, employee, null);

            if (actingUserId != Guid.Empty)
                return (actingUserId, employee, null);

            return (null, employee, "Không xác định được người tạo yêu cầu");
        }

        if (actingUserId != Guid.Empty)
            return (actingUserId, null, null);

        return (null, null, "Không tìm thấy nhân viên");
    }

    /// <summary>
    /// Resolves the HR employee row for applying a correction (by code/PIN first, then user id).
    /// </summary>
    public static async Task<Employee?> ResolveEmployeeEntityAsync(
        IRepository<Employee> employeeRepository,
        IRepository<DeviceUser> deviceUserRepository,
        Guid? storeId,
        string? employeeCode,
        Guid? applicationUserId,
        CancellationToken cancellationToken = default)
    {
        if (storeId.HasValue)
        {
            var byProfile = await FindEmployeeAsync(
                employeeRepository, deviceUserRepository, storeId.Value,
                employeeCode, employeeCode, cancellationToken);
            if (byProfile != null)
                return byProfile;
        }

        if (applicationUserId.HasValue && applicationUserId.Value != Guid.Empty)
        {
            return await employeeRepository.GetSingleAsync(
                e => e.ApplicationUserId == applicationUserId,
                cancellationToken: cancellationToken);
        }

        return null;
    }

    private static async Task<Employee?> FindEmployeeAsync(
        IRepository<Employee> employeeRepository,
        IRepository<DeviceUser> deviceUserRepository,
        Guid storeId,
        string? employeeCode,
        string? pin,
        CancellationToken cancellationToken)
    {
        var keys = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        if (!string.IsNullOrWhiteSpace(employeeCode))
            keys.Add(employeeCode.Trim());
        if (!string.IsNullOrWhiteSpace(pin))
            keys.Add(pin.Trim());

        foreach (var key in keys)
        {
            var employee = await employeeRepository.GetSingleAsync(
                e => e.StoreId == storeId && e.EmployeeCode == key,
                cancellationToken: cancellationToken);
            if (employee != null)
                return employee;

            var deviceUser = await deviceUserRepository.GetSingleAsync(
                du => du.Pin == key,
                includeProperties: ["Employee", "Device"],
                cancellationToken: cancellationToken);
            if (deviceUser?.EmployeeId == null)
                continue;

            employee = await employeeRepository.GetByIdAsync(
                deviceUser.EmployeeId.Value, cancellationToken: cancellationToken);
            if (employee != null && employee.StoreId == storeId)
                return employee;
        }

        return null;
    }
}

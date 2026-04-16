namespace ZKTecoADMS.Application.Interfaces;

/// <summary>
/// Service phân quyền dữ liệu theo phòng ban.
/// Xác định user quản lý phòng ban nào, nhân viên nào.
/// </summary>
public interface IDataScopeService
{
    /// <summary>
    /// Lấy danh sách DepartmentId mà user quản lý (bao gồm PB con nếu IncludeChildren)
    /// </summary>
    Task<List<Guid>> GetManagedDepartmentIdsAsync(Guid userId, Guid storeId);

    /// <summary>
    /// Lấy danh sách EmployeeId thuộc phạm vi quản lý của user
    /// (NV trong phòng ban quản lý + NV báo cáo trực tiếp)
    /// </summary>
    Task<List<Guid>> GetSubordinateEmployeeIdsAsync(Guid userId, Guid storeId);

    /// <summary>
    /// Lấy danh sách ApplicationUserId thuộc phạm vi quản lý của user
    /// </summary>
    Task<List<Guid>> GetSubordinateUserIdsAsync(Guid userId, Guid storeId);

    /// <summary>
    /// Kiểm tra user có quyền xem dữ liệu của employee không
    /// </summary>
    Task<bool> CanAccessEmployeeDataAsync(Guid userId, Guid employeeId, Guid storeId);
}

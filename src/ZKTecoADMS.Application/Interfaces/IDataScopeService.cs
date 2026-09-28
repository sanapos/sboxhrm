namespace ZKTecoADMS.Application.Interfaces;

/// <summary>
/// Service phân quyền dữ liệu theo phòng ban và chi nhánh.
/// Xác định user quản lý phòng ban nào, chi nhánh nào, nhân viên nào.
/// </summary>
public interface IDataScopeService
{
    /// <summary>
    /// Lấy danh sách DepartmentId mà user quản lý (bao gồm PB con nếu IncludeChildren)
    /// </summary>
    Task<List<Guid>> GetManagedDepartmentIdsAsync(Guid userId, Guid storeId);

    /// <summary>
    /// Lấy danh sách BranchId mà user quản lý
    /// (là Branch.ManagerId hoặc được phân quyền qua BranchPermission)
    /// </summary>
    Task<List<Guid>> GetManagedBranchIdsAsync(Guid userId, Guid storeId);

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

    /// <summary>
    /// Quyền Tạo / Sửa / Xóa dữ liệu thuộc chi nhánh <paramref name="branchId"/> theo BranchPermission.
    /// Chỉ chặn khi quyền của user với chi nhánh này đến TỪ BranchPermission mà thiếu cờ tương ứng;
    /// quản lý chi nhánh (Branch.ManagerId) và người có quyền theo phòng ban / cấp trên trực tiếp không bị ảnh hưởng.
    /// </summary>
    Task<bool> CanActOnBranchAsync(Guid userId, Guid storeId, Guid? branchId, BranchAction action);
}

public enum BranchAction
{
    Create,
    Edit,
    Delete,
}

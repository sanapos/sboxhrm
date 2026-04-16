namespace ZKTecoADMS.Application.DTOs.Permissions;

/// <summary>
/// DTO cho Permission (Module)
/// </summary>
public class PermissionDto
{
    public Guid Id { get; set; }
    public string Module { get; set; } = string.Empty;
    public string ModuleDisplayName { get; set; } = string.Empty;
    public string? Description { get; set; }
    public int DisplayOrder { get; set; }
}

/// <summary>
/// DTO cho RolePermission
/// </summary>
public class RolePermissionDto
{
    public Guid Id { get; set; }
    public string RoleName { get; set; } = string.Empty;
    public string RoleDisplayName { get; set; } = string.Empty;
    public Guid PermissionId { get; set; }
    public string Module { get; set; } = string.Empty;
    public string ModuleDisplayName { get; set; } = string.Empty;
    public Guid? StoreId { get; set; }
    public string? StoreName { get; set; }
    public bool CanView { get; set; }
    public bool CanCreate { get; set; }
    public bool CanEdit { get; set; }
    public bool CanDelete { get; set; }
    public bool CanExport { get; set; }
    public bool CanApprove { get; set; }
    public bool IsActive { get; set; }
    public DateTime CreatedAt { get; set; }
    public string? CreatedBy { get; set; }
}

/// <summary>
/// DTO nhóm quyền theo Role
/// </summary>
public class RolePermissionGroupDto
{
    public string RoleName { get; set; } = string.Empty;
    public string RoleDisplayName { get; set; } = string.Empty;
    public Guid? StoreId { get; set; }
    public string? StoreName { get; set; }
    public List<ModulePermissionDto> Permissions { get; set; } = [];
}

/// <summary>
/// DTO quyền của một module
/// </summary>
public class ModulePermissionDto
{
    public Guid PermissionId { get; set; }
    public string Module { get; set; } = string.Empty;
    public string ModuleDisplayName { get; set; } = string.Empty;
    public int DisplayOrder { get; set; }
    public bool CanView { get; set; }
    public bool CanCreate { get; set; }
    public bool CanEdit { get; set; }
    public bool CanDelete { get; set; }
    public bool CanExport { get; set; }
    public bool CanApprove { get; set; }
}

/// <summary>
/// Request tạo/cập nhật RolePermission
/// </summary>
public class CreateRolePermissionRequest
{
    public string RoleName { get; set; } = string.Empty;
    public string RoleDisplayName { get; set; } = string.Empty;
    public Guid? StoreId { get; set; }
    public List<ModulePermissionRequest> Permissions { get; set; } = [];
}

/// <summary>
/// Request quyền cho một module
/// </summary>
public class ModulePermissionRequest
{
    public Guid PermissionId { get; set; }
    public bool CanView { get; set; }
    public bool CanCreate { get; set; }
    public bool CanEdit { get; set; }
    public bool CanDelete { get; set; }
    public bool CanExport { get; set; }
    public bool CanApprove { get; set; }
}

/// <summary>
/// Request tạo Role mới (chức danh)
/// </summary>
public class CreateRoleRequest
{
    public string RoleName { get; set; } = string.Empty;
    public string RoleDisplayName { get; set; } = string.Empty;
    public Guid? StoreId { get; set; }
}

/// <summary>
/// Response danh sách chức danh (role)
/// </summary>
public class RoleDto
{
    public string RoleName { get; set; } = string.Empty;
    public string RoleDisplayName { get; set; } = string.Empty;
    public int PermissionCount { get; set; }
    public Guid? StoreId { get; set; }
    public string? StoreName { get; set; }
}

// ============================================================
// Department Permission DTOs
// ============================================================

/// <summary>
/// DTO cho DepartmentPermission
/// </summary>
public class DepartmentPermissionDto
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public string? UserName { get; set; }
    public string? FullName { get; set; }
    public Guid? DepartmentId { get; set; }
    public string? DepartmentName { get; set; }
    public Guid PermissionId { get; set; }
    public string Module { get; set; } = string.Empty;
    public string ModuleDisplayName { get; set; } = string.Empty;
    public bool IncludeChildren { get; set; }
    public Guid? StoreId { get; set; }
    public bool CanView { get; set; }
    public bool CanCreate { get; set; }
    public bool CanEdit { get; set; }
    public bool CanDelete { get; set; }
    public bool CanExport { get; set; }
    public bool CanApprove { get; set; }
    public bool IsActive { get; set; }
    public string? GrantedBy { get; set; }
    public string? Note { get; set; }
    public DateTime CreatedAt { get; set; }
}

/// <summary>
/// DTO nhóm quyền phòng ban theo User
/// </summary>
public class UserDepartmentPermissionGroupDto
{
    public Guid UserId { get; set; }
    public string? UserName { get; set; }
    public string? FullName { get; set; }
    public List<DepartmentPermissionItemDto> DepartmentPermissions { get; set; } = [];
}

/// <summary>
/// DTO quyền theo phòng ban (mỗi phòng ban có danh sách modules)
/// </summary>
public class DepartmentPermissionItemDto
{
    public Guid? DepartmentId { get; set; }
    public string? DepartmentName { get; set; }
    public bool IncludeChildren { get; set; }
    public List<ModulePermissionDto> Permissions { get; set; } = [];
}

/// <summary>
/// Request tạo/cập nhật DepartmentPermission
/// </summary>
public class CreateDepartmentPermissionRequest
{
    public Guid UserId { get; set; }
    public Guid? DepartmentId { get; set; }
    public bool IncludeChildren { get; set; } = true;
    public Guid? StoreId { get; set; }
    public string? Note { get; set; }
    public List<ModulePermissionRequest> Permissions { get; set; } = [];
}

/// <summary>
/// DTO cây phòng ban kèm thông tin quyền
/// </summary>
public class DepartmentTreeNodeDto
{
    public Guid Id { get; set; }
    public string Code { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public Guid? ParentDepartmentId { get; set; }
    public int Level { get; set; }
    public string? ManagerName { get; set; }
    public Guid? ManagerId { get; set; }
    public int EmployeeCount { get; set; }
    public int PermissionCount { get; set; }
    public List<DepartmentTreeNodeDto> Children { get; set; } = [];
}

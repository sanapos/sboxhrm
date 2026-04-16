using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Định nghĩa một quyền cụ thể trong hệ thống
/// </summary>
public class Permission : Entity<Guid>
{
    /// <summary>
    /// Tên module (ví dụ: Employee, Attendance, Salary, Device, etc.)
    /// </summary>
    public string Module { get; set; } = string.Empty;
    
    /// <summary>
    /// Tên hiển thị của module
    /// </summary>
    public string ModuleDisplayName { get; set; } = string.Empty;
    
    /// <summary>
    /// Mô tả quyền
    /// </summary>
    public string? Description { get; set; }
    
    /// <summary>
    /// Thứ tự hiển thị
    /// </summary>
    public int DisplayOrder { get; set; }
    
    /// <summary>
    /// Danh sách RolePermission liên kết
    /// </summary>
    public virtual ICollection<RolePermission> RolePermissions { get; set; } = [];
}

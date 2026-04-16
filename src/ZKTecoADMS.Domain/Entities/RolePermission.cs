using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Định nghĩa quyền của một Role đối với một Module
/// </summary>
public class RolePermission : Entity<Guid>
{
    /// <summary>
    /// Tên chức danh (ví dụ: Admin, Manager, Accountant, Employee, User)
    /// </summary>
    public string RoleName { get; set; } = string.Empty;
    
    /// <summary>
    /// Tên hiển thị của chức danh (ví dụ: Quản trị viên, Quản lý, Kế toán, Nhân viên)
    /// </summary>
    public string RoleDisplayName { get; set; } = string.Empty;
    
    /// <summary>
    /// Liên kết đến Permission
    /// </summary>
    public Guid PermissionId { get; set; }
    public virtual Permission Permission { get; set; } = null!;
    
    /// <summary>
    /// Thuộc về Store nào (nullable cho system-wide roles)
    /// </summary>
    public Guid? StoreId { get; set; }
    public virtual Store? Store { get; set; }
    
    /// <summary>
    /// Quyền xem
    /// </summary>
    public bool CanView { get; set; }
    
    /// <summary>
    /// Quyền thêm mới
    /// </summary>
    public bool CanCreate { get; set; }
    
    /// <summary>
    /// Quyền sửa
    /// </summary>
    public bool CanEdit { get; set; }
    
    /// <summary>
    /// Quyền xóa
    /// </summary>
    public bool CanDelete { get; set; }
    
    /// <summary>
    /// Quyền xuất báo cáo
    /// </summary>
    public bool CanExport { get; set; }
    
    /// <summary>
    /// Quyền duyệt (đơn từ, yêu cầu, etc.)
    /// </summary>
    public bool CanApprove { get; set; }
    
    /// <summary>
    /// Trạng thái hoạt động
    /// </summary>
    public bool IsActive { get; set; } = true;
    
    /// <summary>
    /// Ngày tạo
    /// </summary>
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    
    /// <summary>
    /// Người tạo
    /// </summary>
    public string? CreatedBy { get; set; }
}

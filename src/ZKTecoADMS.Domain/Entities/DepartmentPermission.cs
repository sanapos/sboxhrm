using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Phân quyền theo phòng ban - gán quyền cho user trong phạm vi phòng ban cụ thể.
/// Manager của phòng ban sẽ có quyền quản lý NV thuộc phòng ban đó + phòng ban con.
/// </summary>
public class DepartmentPermission : Entity<Guid>
{
    /// <summary>
    /// User được phân quyền (ApplicationUserId)
    /// </summary>
    public Guid UserId { get; set; }
    public virtual ApplicationUser? User { get; set; }

    /// <summary>
    /// Phòng ban áp dụng (null = tất cả phòng ban)
    /// </summary>
    public Guid? DepartmentId { get; set; }
    public virtual Department? Department { get; set; }

    /// <summary>
    /// Module áp dụng quyền
    /// </summary>
    public Guid PermissionId { get; set; }
    public virtual Permission? Permission { get; set; }

    /// <summary>
    /// Có áp dụng cho phòng ban con không
    /// </summary>
    public bool IncludeChildren { get; set; } = true;

    /// <summary>
    /// Store
    /// </summary>
    public Guid? StoreId { get; set; }
    public virtual Store? Store { get; set; }

    // Permission flags
    public bool CanView { get; set; }
    public bool CanCreate { get; set; }
    public bool CanEdit { get; set; }
    public bool CanDelete { get; set; }
    public bool CanExport { get; set; }
    public bool CanApprove { get; set; }

    public bool IsActive { get; set; } = true;

    /// <summary>
    /// Phân quyền bởi ai
    /// </summary>
    public string? GrantedBy { get; set; }

    /// <summary>
    /// Ghi chú
    /// </summary>
    public string? Note { get; set; }
}

using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Phân quyền theo chi nhánh — gán quyền xem/quản lý nhân viên của chi nhánh cho user.
/// Branch manager trong Branch.ManagerId tự động có quyền; bảng này dùng để cấp thêm.
/// </summary>
public class BranchPermission : Entity<Guid>
{
    /// <summary>User được phân quyền (ApplicationUser.Id)</summary>
    public Guid UserId { get; set; }
    public virtual ApplicationUser? User { get; set; }

    /// <summary>Chi nhánh áp dụng (null = tất cả chi nhánh trong store)</summary>
    public Guid? BranchId { get; set; }
    public virtual Branch? Branch { get; set; }

    /// <summary>Có áp dụng cho chi nhánh con không</summary>
    public bool IncludeChildren { get; set; } = true;

    /// <summary>Store (tenant)</summary>
    public Guid? StoreId { get; set; }
    public virtual Store? Store { get; set; }

    // Permission flags
    public bool CanView { get; set; } = true;
    public bool CanCreate { get; set; }
    public bool CanEdit { get; set; }
    public bool CanDelete { get; set; }

    public bool IsActive { get; set; } = true;

    /// <summary>Phân quyền bởi ai</summary>
    public string? GrantedBy { get; set; }

    /// <summary>Ghi chú</summary>
    public string? Note { get; set; }
}

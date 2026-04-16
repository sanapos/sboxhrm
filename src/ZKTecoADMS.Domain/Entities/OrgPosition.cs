using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Chức vụ trong tổ chức (Giám đốc, Trưởng phòng, Phó phòng, Nhân viên...)
/// Dùng làm cơ sở xét chế độ duyệt theo cấp bậc
/// </summary>
public class OrgPosition : AuditableEntity<Guid>
{
    /// <summary>
    /// Mã chức vụ (GD, TP, PP, NV...)
    /// </summary>
    [Required]
    [MaxLength(20)]
    public string Code { get; set; } = string.Empty;

    /// <summary>
    /// Tên chức vụ
    /// </summary>
    [Required]
    [MaxLength(200)]
    public string Name { get; set; } = string.Empty;

    /// <summary>
    /// Mô tả chức vụ
    /// </summary>
    [MaxLength(500)]
    public string? Description { get; set; }

    /// <summary>
    /// Cấp bậc (số càng nhỏ = quyền càng cao). VD: 1=Giám đốc, 2=Phó GĐ, 3=Trưởng phòng, 4=Phó phòng, 5=Nhân viên
    /// Dùng để xác định ai được duyệt cho ai trong ApprovalFlow
    /// </summary>
    public int Level { get; set; }

    /// <summary>
    /// Thứ tự hiển thị
    /// </summary>
    public int SortOrder { get; set; }

    /// <summary>
    /// Màu hiển thị trên sơ đồ tổ chức (hex color)
    /// </summary>
    [MaxLength(10)]
    public string? Color { get; set; }

    /// <summary>
    /// Icon hiển thị (material icon name)
    /// </summary>
    [MaxLength(50)]
    public string? IconName { get; set; }

    /// <summary>
    /// Có quyền duyệt hay không
    /// </summary>
    public bool CanApprove { get; set; }

    /// <summary>
    /// Mức duyệt tối đa (VD: trưởng phòng duyệt tối đa 5 triệu, GĐ duyệt tối đa 50 triệu)
    /// </summary>
    public decimal? MaxApprovalAmount { get; set; }

    /// <summary>
    /// Cửa hàng/Chi nhánh
    /// </summary>
    public Guid? StoreId { get; set; }
    public virtual Store? Store { get; set; }

    /// <summary>
    /// Danh sách nhân viên giữ chức vụ này
    /// </summary>
    public virtual ICollection<OrgAssignment> OrgAssignments { get; set; } = new List<OrgAssignment>();
}

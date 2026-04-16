using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Cấu hình luồng duyệt cho từng loại yêu cầu
/// VD: nghỉ phép → TP duyệt → GĐ duyệt, tăng ca → TP duyệt...
/// </summary>
public class ApprovalFlow : AuditableEntity<Guid>
{
    /// <summary>
    /// Mã luồng duyệt
    /// </summary>
    [Required]
    [MaxLength(50)]
    public string Code { get; set; } = string.Empty;

    /// <summary>
    /// Tên luồng duyệt
    /// </summary>
    [Required]
    [MaxLength(200)]
    public string Name { get; set; } = string.Empty;

    /// <summary>
    /// Mô tả
    /// </summary>
    [MaxLength(500)]
    public string? Description { get; set; }

    /// <summary>
    /// Loại yêu cầu áp dụng luồng duyệt
    /// </summary>
    public ApprovalRequestType RequestType { get; set; }

    /// <summary>
    /// Phòng ban áp dụng (null = áp dụng cho tất cả phòng ban)
    /// </summary>
    public Guid? DepartmentId { get; set; }
    public virtual Department? Department { get; set; }

    /// <summary>
    /// Thứ tự ưu tiên (khi có nhiều flow cho cùng request type, ưu tiên flow có priority cao hơn)
    /// </summary>
    public int Priority { get; set; }

    /// <summary>
    /// Cửa hàng/Chi nhánh
    /// </summary>
    public Guid? StoreId { get; set; }
    public virtual Store? Store { get; set; }

    /// <summary>
    /// Danh sách các bước duyệt
    /// </summary>
    public virtual ICollection<ApprovalStep> Steps { get; set; } = new List<ApprovalStep>();
}

/// <summary>
/// Một bước trong luồng duyệt
/// </summary>
public class ApprovalStep : AuditableEntity<Guid>
{
    /// <summary>
    /// Luồng duyệt chứa bước này
    /// </summary>
    public Guid ApprovalFlowId { get; set; }
    public virtual ApprovalFlow? ApprovalFlow { get; set; }

    /// <summary>
    /// Thứ tự bước (1, 2, 3...)
    /// </summary>
    public int StepOrder { get; set; }

    /// <summary>
    /// Tên bước duyệt
    /// </summary>
    [Required]
    [MaxLength(200)]
    public string Name { get; set; } = string.Empty;

    /// <summary>
    /// Loại người duyệt
    /// </summary>
    public ApproverType ApproverType { get; set; }

    /// <summary>
    /// ID chức vụ duyệt (nếu ApproverType = ByPosition)
    /// </summary>
    public Guid? ApproverPositionId { get; set; }
    public virtual OrgPosition? ApproverPosition { get; set; }

    /// <summary>
    /// ID nhân viên duyệt cụ thể (nếu ApproverType = SpecificEmployee)
    /// </summary>
    public Guid? ApproverEmployeeId { get; set; }
    public virtual Employee? ApproverEmployee { get; set; }

    /// <summary>
    /// Có bắt buộc duyệt bước này không (false = có thể bỏ qua nếu không có người duyệt)
    /// </summary>
    public bool IsRequired { get; set; } = true;

    /// <summary>
    /// Thời gian tối đa chờ duyệt (giờ). Quá thời gian sẽ tự động chuyển bước tiếp hoặc escalate
    /// </summary>
    public int? MaxWaitHours { get; set; }

    /// <summary>
    /// Hành động khi quá thời gian chờ
    /// </summary>
    public TimeoutAction TimeoutAction { get; set; } = TimeoutAction.Escalate;
}

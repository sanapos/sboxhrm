using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Yêu cầu đổi ca làm việc giữa hai nhân viên
/// </summary>
public class ShiftSwapRequest : AuditableEntity<Guid>
{
    /// <summary>
    /// Cửa hàng/Chi nhánh
    /// </summary>
    [Required]
    public Guid StoreId { get; set; }

    /// <summary>
    /// Nhân viên yêu cầu đổi ca (người khởi tạo)
    /// </summary>
    [Required]
    public Guid RequesterUserId { get; set; }

    /// <summary>
    /// Nhân viên được yêu cầu đổi ca
    /// </summary>
    [Required]
    public Guid TargetUserId { get; set; }

    /// <summary>
    /// Ngày ca của người yêu cầu
    /// </summary>
    [Required]
    public DateTime RequesterDate { get; set; }

    /// <summary>
    /// Ca làm việc của người yêu cầu
    /// </summary>
    [Required]
    public Guid RequesterShiftId { get; set; }

    /// <summary>
    /// Ngày ca của người được yêu cầu
    /// </summary>
    [Required]
    public DateTime TargetDate { get; set; }

    /// <summary>
    /// Ca làm việc của người được yêu cầu
    /// </summary>
    [Required]
    public Guid TargetShiftId { get; set; }

    /// <summary>
    /// Lý do đổi ca
    /// </summary>
    [MaxLength(500)]
    public string? Reason { get; set; }

    /// <summary>
    /// Trạng thái yêu cầu
    /// </summary>
    [Required]
    public ShiftSwapStatus Status { get; set; } = ShiftSwapStatus.Pending;

    /// <summary>
    /// Người được yêu cầu đã chấp nhận?
    /// </summary>
    public bool TargetAccepted { get; set; } = false;

    /// <summary>
    /// Ngày người được yêu cầu phản hồi
    /// </summary>
    public DateTime? TargetResponseDate { get; set; }

    /// <summary>
    /// Quản lý phê duyệt
    /// </summary>
    public Guid? ApprovedByManagerId { get; set; }

    /// <summary>
    /// Ngày quản lý phê duyệt
    /// </summary>
    public DateTime? ManagerApprovalDate { get; set; }

    /// <summary>
    /// Lý do từ chối (từ người được yêu cầu hoặc quản lý)
    /// </summary>
    [MaxLength(500)]
    public string? RejectionReason { get; set; }

    /// <summary>
    /// Ghi chú bổ sung
    /// </summary>
    [MaxLength(500)]
    public string? Note { get; set; }

    // Navigation Properties
    public virtual Store Store { get; set; } = null!;
    public virtual ApplicationUser RequesterUser { get; set; } = null!;
    public virtual ApplicationUser TargetUser { get; set; } = null!;
    public virtual Shift RequesterShift { get; set; } = null!;
    public virtual Shift TargetShift { get; set; } = null!;
    public virtual ApplicationUser? ApprovedByManager { get; set; }
}

using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Yêu cầu sửa chấm công - Attendance Correction Request
/// </summary>
public class AttendanceCorrectionRequest : AuditableEntity<Guid>
{
    [Required]
    public Guid EmployeeUserId { get; set; }

    [MaxLength(100)]
    public string? EmployeeName { get; set; }

    [MaxLength(50)]
    public string? EmployeeCode { get; set; }

    /// <summary>
    /// Loại hành động: Thêm mới / Sửa / Xóa
    /// </summary>
    [Required]
    public CorrectionAction Action { get; set; }

    /// <summary>
    /// ID bản ghi chấm công cần sửa (nếu là Sửa hoặc Xóa)
    /// </summary>
    public Guid? AttendanceId { get; set; }

    /// <summary>
    /// Ngày cũ (trước khi sửa)
    /// </summary>
    public DateTime? OldDate { get; set; }

    /// <summary>
    /// Giờ cũ (trước khi sửa)
    /// </summary>
    public TimeSpan? OldTime { get; set; }

    /// <summary>
    /// Thiết bị cũ
    /// </summary>
    [MaxLength(100)]
    public string? OldDevice { get; set; }

    /// <summary>
    /// Loại chấm công cũ
    /// </summary>
    [MaxLength(50)]
    public string? OldType { get; set; }

    /// <summary>
    /// Ngày mới (sau khi sửa)
    /// </summary>
    public DateTime? NewDate { get; set; }

    /// <summary>
    /// Giờ mới (sau khi sửa)
    /// </summary>
    public TimeSpan? NewTime { get; set; }

    /// <summary>
    /// Lý do yêu cầu sửa
    /// </summary>
    [Required]
    [MaxLength(1000)]
    public string Reason { get; set; } = string.Empty;

    /// <summary>
    /// Trạng thái yêu cầu
    /// </summary>
    [Required]
    public CorrectionStatus Status { get; set; } = CorrectionStatus.Pending;

    /// <summary>
    /// Người duyệt
    /// </summary>
    public Guid? ApprovedById { get; set; }

    /// <summary>
    /// Ngày duyệt
    /// </summary>
    public DateTime? ApprovedDate { get; set; }

    /// <summary>
    /// Ghi chú của người duyệt
    /// </summary>
    [MaxLength(500)]
    public string? ApproverNote { get; set; }

    /// <summary>
    /// Tổng số cấp duyệt (từ setting tại thời điểm tạo)
    /// </summary>
    public int TotalApprovalLevels { get; set; } = 1;

    /// <summary>
    /// Bước duyệt hiện tại (0 = chưa ai duyệt, 1 = cấp 1 đã duyệt...)
    /// </summary>
    public int CurrentApprovalStep { get; set; } = 0;
    
    /// <summary>
    /// Cửa hàng liên quan
    /// </summary>
    public Guid? StoreId { get; set; }
    public virtual Store? Store { get; set; }

    // Navigation Properties
    public virtual ApplicationUser EmployeeUser { get; set; } = null!;
    public virtual ApplicationUser? ApprovedBy { get; set; }
    public virtual Attendance? Attendance { get; set; }
    public virtual ICollection<ApprovalRecord> ApprovalRecords { get; set; } = new List<ApprovalRecord>();
}

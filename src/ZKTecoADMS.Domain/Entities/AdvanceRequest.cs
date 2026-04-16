using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Yêu cầu ứng lương - Advance Salary Request
/// </summary>
public class AdvanceRequest : AuditableEntity<Guid>
{
    public Guid? EmployeeUserId { get; set; }

    /// <summary>
    /// Nhân viên liên quan
    /// </summary>
    public Guid? EmployeeId { get; set; }
    public virtual Employee? Employee { get; set; }

    /// <summary>
    /// Số tiền yêu cầu ứng
    /// </summary>
    [Required]
    public decimal Amount { get; set; }

    /// <summary>
    /// Lý do ứng lương
    /// </summary>
    [Required]
    [MaxLength(1000)]
    public string Reason { get; set; } = string.Empty;

    /// <summary>
    /// Ngày yêu cầu
    /// </summary>
    [Required]
    public DateTime RequestDate { get; set; } = DateTime.UtcNow;

    /// <summary>
    /// Trạng thái yêu cầu
    /// </summary>
    [Required]
    public AdvanceRequestStatus Status { get; set; } = AdvanceRequestStatus.Pending;

    /// <summary>
    /// Người duyệt
    /// </summary>
    public Guid? ApprovedById { get; set; }

    /// <summary>
    /// Ngày duyệt
    /// </summary>
    public DateTime? ApprovedDate { get; set; }

    /// <summary>
    /// Lý do từ chối (nếu có)
    /// </summary>
    [MaxLength(500)]
    public string? RejectionReason { get; set; }

    /// <summary>
    /// Ghi chú
    /// </summary>
    [MaxLength(500)]
    public string? Note { get; set; }

    /// <summary>
    /// Đã thanh toán chưa
    /// </summary>
    public bool IsPaid { get; set; }

    /// <summary>
    /// Phương thức thanh toán (khi đã thanh toán)
    /// </summary>
    [MaxLength(50)]
    public string? PaymentMethod { get; set; }

    /// <summary>
    /// Ngày thanh toán
    /// </summary>
    public DateTime? PaidDate { get; set; }

    /// <summary>
    /// Tháng/năm liên quan
    /// </summary>
    public int? ForMonth { get; set; }
    public int? ForYear { get; set; }
    
    /// <summary>
    /// Cửa hàng liên quan
    /// </summary>
    public Guid? StoreId { get; set; }
    public virtual Store? Store { get; set; }

    /// <summary>
    /// Duyệt đa cấp
    /// </summary>
    public int TotalApprovalLevels { get; set; } = 1;
    public int CurrentApprovalStep { get; set; } = 0;

    // Navigation Properties
    public virtual ApplicationUser? EmployeeUser { get; set; }
    public virtual ApplicationUser? ApprovedBy { get; set; }
    public virtual ICollection<AdvanceApprovalRecord> ApprovalRecords { get; set; } = [];
}

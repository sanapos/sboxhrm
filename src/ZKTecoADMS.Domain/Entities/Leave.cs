using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Domain.Entities;

public class Leave : AuditableEntity<Guid>
{
    [Required]
    public Guid EmployeeUserId { get; set; }

    [Required]
    public Guid ManagerId { get; set; }
    
    [Required]
    public LeaveType Type { get; set; }

    [Required]
    public Guid ShiftId { get; set; }

    [Required]
    public DateTime StartDate { get; set; }

    [Required]
    public DateTime EndDate { get; set; }
    
    [Required]
    public bool IsHalfShift { get; set; }
    
    [Required]
    [MaxLength(1000)]
    public string Reason { get; set; } = string.Empty;
    
    [Required]
    public LeaveStatus Status { get; set; } = LeaveStatus.Pending;
    
    [MaxLength(500)]
    public string? RejectionReason { get; set; }
    
    /// <summary>
    /// Cửa hàng mà đơn nghỉ phép thuộc về
    /// </summary>
    public Guid? StoreId { get; set; }
    public virtual Store? Store { get; set; }
    
    public List<Guid> ShiftIds { get; set; } = new List<Guid>();
    public Guid? ReplacementEmployeeId { get; set; }
    public Guid? EmployeeId { get; set; }

    /// <summary>
    /// Tổng số cấp duyệt
    /// </summary>
    public int TotalApprovalLevels { get; set; } = 1;

    /// <summary>
    /// Bước duyệt hiện tại (0 = chưa ai duyệt)
    /// </summary>
    public int CurrentApprovalStep { get; set; } = 0;

    /// <summary>
    /// Đơn đã duyệt nhưng vẫn tính công (không đánh dấu vắng/phép trên chấm công).
    /// </summary>
    public bool CountAsWork { get; set; }

    /// <summary>DN trả lương / không lương / BHXH / thai sản đối soát.</summary>
    public LeavePaymentSource PaymentSource { get; set; }

    /// <summary>Ốm: dùng phép năm hay hưởng BHXH.</summary>
    public SickLeaveMode SickLeaveMode { get; set; }

    /// <summary>Số giấy nghỉ BHXH hoặc ghi chú hồ sơ (ốm BHXH, thai sản).</summary>
    [MaxLength(500)]
    public string? BhxhDocumentNote { get; set; }

    /// <summary>Số ngày phép năm đã trừ khi duyệt (để hoàn lại).</summary>
    public decimal AnnualLeaveDaysDeducted { get; set; }

    /// <summary>Đã trừ vào quỹ phép năm (EmployeeBenefit).</summary>
    public bool AnnualBalanceApplied { get; set; }

    // Navigation Properties
    public virtual ApplicationUser EmployeeUser { get; set; } = null!;
    public virtual ApplicationUser Manager { get; set; } = null!;
    public virtual ShiftTemplate? Shift { get; set; }
    public virtual Employee? ReplacementEmployee { get; set; }
    public virtual ICollection<LeaveApprovalRecord> ApprovalRecords { get; set; } = new List<LeaveApprovalRecord>();
}

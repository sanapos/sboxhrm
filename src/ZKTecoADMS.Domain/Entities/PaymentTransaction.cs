using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Giao dịch thu chi lương - Payment Transaction
/// </summary>
public class PaymentTransaction : AuditableEntity<Guid>
{
    public Guid? EmployeeUserId { get; set; }

    /// <summary>
    /// ID nhân viên (FK → Employees)
    /// </summary>
    public Guid? EmployeeId { get; set; }

    /// <summary>
    /// Loại giao dịch: Ứng lương, Thưởng, Phạt, Thanh toán lương, Khác
    /// </summary>
    [Required]
    [MaxLength(100)]
    public string Type { get; set; } = string.Empty;

    /// <summary>
    /// Tháng/năm liên quan
    /// </summary>
    public int? ForMonth { get; set; }
    public int? ForYear { get; set; }

    /// <summary>
    /// Ngày giao dịch
    /// </summary>
    [Required]
    public DateTime TransactionDate { get; set; } = DateTime.UtcNow;

    /// <summary>
    /// Số tiền (dương = nhận, âm = trừ)
    /// </summary>
    [Required]
    public decimal Amount { get; set; }

    /// <summary>
    /// Nội dung/mô tả
    /// </summary>
    [MaxLength(500)]
    public string? Description { get; set; }

    /// <summary>
    /// Phương thức thanh toán
    /// </summary>
    [MaxLength(100)]
    public string? PaymentMethod { get; set; }

    /// <summary>
    /// Trạng thái: Pending, Completed, Cancelled
    /// </summary>
    [Required]
    [MaxLength(50)]
    public string Status { get; set; } = "Completed";

    /// <summary>
    /// Người thực hiện
    /// </summary>
    public Guid? PerformedById { get; set; }

    /// <summary>
    /// Ghi chú
    /// </summary>
    [MaxLength(500)]
    public string? Note { get; set; }

    /// <summary>
    /// ID yêu cầu ứng lương liên quan (nếu có)
    /// </summary>
    public Guid? AdvanceRequestId { get; set; }

    /// <summary>
    /// ID phiếu lương liên quan (nếu có)
    /// </summary>
    public Guid? PayslipId { get; set; }

    // Navigation Properties
    public virtual ApplicationUser? EmployeeUser { get; set; }
    public virtual Employee? Employee { get; set; }
    public virtual ApplicationUser? PerformedBy { get; set; }
    public virtual AdvanceRequest? AdvanceRequest { get; set; }
    public virtual Payslip? Payslip { get; set; }
}

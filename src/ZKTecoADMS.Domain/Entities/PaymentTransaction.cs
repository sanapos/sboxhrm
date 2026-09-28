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

    // ─── Tài chính nhân sự v2 ───

    /// <summary>Nguồn: manual / kpi / attendance</summary>
    [MaxLength(20)]
    public string? Source { get; set; }

    /// <summary>Cách xử lý tiền: salary = cộng/trừ vào lương; cash = chi/thu tiền mặt (lương bỏ qua)</summary>
    [MaxLength(10)]
    public string? Settlement { get; set; }

    /// <summary>Phiếu thu/chi tiền mặt liên kết (khi Settlement = cash)</summary>
    public Guid? CashTransactionId { get; set; }

    /// <summary>JSON mảng URL ảnh / tệp bằng chứng</summary>
    public string? EvidenceUrls { get; set; }

    /// <summary>0 = không khiếu nại, 1 = đang khiếu nại, 2 = chấp nhận (đã hủy phiếu), 3 = bác khiếu nại</summary>
    public int DisputeStatus { get; set; }

    [MaxLength(1000)]
    public string? DisputeReason { get; set; }

    public DateTime? DisputedAt { get; set; }

    [MaxLength(1000)]
    public string? DisputeResponse { get; set; }

    // Navigation Properties
    public virtual ApplicationUser? EmployeeUser { get; set; }
    public virtual Employee? Employee { get; set; }
    public virtual ApplicationUser? PerformedBy { get; set; }
    public virtual AdvanceRequest? AdvanceRequest { get; set; }
    public virtual Payslip? Payslip { get; set; }
}

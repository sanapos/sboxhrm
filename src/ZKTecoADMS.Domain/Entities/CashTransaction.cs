using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Giao dịch thu chi - Income/Expense Transaction
/// </summary>
public class CashTransaction : AuditableEntity<Guid>
{
    /// <summary>
    /// Mã giao dịch (tự động sinh: TC-YYYYMMDD-XXXX)
    /// </summary>
    [Required]
    [MaxLength(50)]
    public string TransactionCode { get; set; } = string.Empty;

    /// <summary>
    /// Loại giao dịch: Income (Thu) hoặc Expense (Chi)
    /// </summary>
    [Required]
    public CashTransactionType Type { get; set; }

    /// <summary>
    /// Danh mục giao dịch
    /// </summary>
    [Required]
    public Guid CategoryId { get; set; }

    /// <summary>
    /// Số tiền (luôn dương)
    /// </summary>
    [Required]
    public decimal Amount { get; set; }

    /// <summary>
    /// Ngày giao dịch
    /// </summary>
    [Required]
    public DateTime TransactionDate { get; set; } = DateTime.UtcNow;

    /// <summary>
    /// Nội dung/mô tả giao dịch
    /// </summary>
    [Required]
    [MaxLength(500)]
    public string Description { get; set; } = string.Empty;

    /// <summary>
    /// Phương thức thanh toán: Cash, BankTransfer, VietQR, Card, Other
    /// </summary>
    [Required]
    public PaymentMethodType PaymentMethod { get; set; } = PaymentMethodType.Cash;

    /// <summary>
    /// Tài khoản ngân hàng liên quan (nếu thanh toán qua ngân hàng)
    /// </summary>
    public Guid? BankAccountId { get; set; }

    /// <summary>
    /// Trạng thái: Pending, Completed, Cancelled
    /// </summary>
    [Required]
    public CashTransactionStatus Status { get; set; } = CashTransactionStatus.Completed;

    /// <summary>
    /// Tên người/đối tác giao dịch
    /// </summary>
    [MaxLength(200)]
    public string? ContactName { get; set; }

    /// <summary>
    /// Số điện thoại người giao dịch
    /// </summary>
    [MaxLength(20)]
    public string? ContactPhone { get; set; }

    /// <summary>
    /// Mã tham chiếu thanh toán (từ ngân hàng)
    /// </summary>
    [MaxLength(100)]
    public string? PaymentReference { get; set; }

    /// <summary>
    /// Link ảnh hóa đơn/chứng từ
    /// </summary>
    [MaxLength(500)]
    public string? ReceiptImageUrl { get; set; }

    /// <summary>
    /// VietQR Payment URL (nếu dùng VietQR)
    /// </summary>
    [MaxLength(1000)]
    public string? VietQRUrl { get; set; }

    /// <summary>
    /// Đã thanh toán chưa
    /// </summary>
    public bool IsPaid { get; set; } = false;

    /// <summary>
    /// Ngày thanh toán
    /// </summary>
    public DateTime? PaidDate { get; set; }

    /// <summary>
    /// Cửa hàng sở hữu giao dịch
    /// </summary>
    public Guid? StoreId { get; set; }
    public virtual Store? Store { get; set; }

    /// <summary>
    /// Người tạo giao dịch
    /// </summary>
    public Guid CreatedByUserId { get; set; }

    /// <summary>
    /// Ghi chú nội bộ
    /// </summary>
    [MaxLength(1000)]
    public string? InternalNote { get; set; }

    /// <summary>
    /// Tags (phân cách bằng dấu phẩy)
    /// </summary>
    [MaxLength(500)]
    public string? Tags { get; set; }

    // Navigation Properties
    public virtual TransactionCategory Category { get; set; } = null!;
    public virtual BankAccount? BankAccount { get; set; }
    public virtual ApplicationUser CreatedByUser { get; set; } = null!;
}

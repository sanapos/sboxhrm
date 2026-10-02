using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>Đợt thanh toán của hợp đồng (đặt cọc, khi giao hàng, nghiệm thu…).</summary>
public class PosQuotePaymentStage : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }

    [Required]
    public Guid QuoteId { get; set; }
    public virtual PosQuote? Quote { get; set; }

    public int SortOrder { get; set; }

    [Required]
    [MaxLength(200)]
    public string Title { get; set; } = string.Empty;

    /// <summary>% trên giá trị hợp đồng — null khi nhập số tiền cố định.</summary>
    public decimal? Percent { get; set; }

    public decimal Amount { get; set; }

    public DateTime? DueDate { get; set; }

    [MaxLength(500)]
    public string? Note { get; set; }
}

/// <summary>Lần thu tiền theo hợp đồng — mỗi lần gắn một phiếu thu quỹ.</summary>
public class PosQuotePayment : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }

    [Required]
    public Guid QuoteId { get; set; }
    public virtual PosQuote? Quote { get; set; }

    /// <summary>Đợt khách nói đang trả (chỉ để hiển thị; số đã thu chia đợt theo thứ tự).</summary>
    public Guid? StageId { get; set; }

    public Guid? CashTransactionId { get; set; }

    public decimal Amount { get; set; }

    public DateTime PaidAt { get; set; } = DateTime.UtcNow;

    [MaxLength(50)]
    public string? PaymentMethod { get; set; }

    public Guid? BankAccountId { get; set; }

    [MaxLength(500)]
    public string? Note { get; set; }

    [MaxLength(200)]
    public string? CollectedBy { get; set; }
}

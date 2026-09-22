using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>Báo giá thương mại — không trừ kho, không ghi doanh thu, không đụng PosSaleOrder.</summary>
public class PosQuote : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    [Required]
    [MaxLength(30)]
    public string QuoteNo { get; set; } = string.Empty;

    public PosQuoteStatus Status { get; set; } = PosQuoteStatus.Draft;

    public Guid? CustomerId { get; set; }
    public virtual PosCustomer? Customer { get; set; }

    [MaxLength(200)]
    public string? CustomerName { get; set; }

    [MaxLength(50)]
    public string? CustomerPhone { get; set; }

    [MaxLength(500)]
    public string? CustomerAddress { get; set; }

    public DateTime? ValidUntil { get; set; }

    public DateTime? IssuedAt { get; set; }

    [MaxLength(200)]
    public string? IssuedBy { get; set; }

    public decimal SubTotal { get; set; }
    public decimal Discount { get; set; }
    public decimal VatAmount { get; set; }
    public decimal Total { get; set; }

    [MaxLength(1000)]
    public string? Note { get; set; }

    [MaxLength(2000)]
    public string? Terms { get; set; }

    [MaxLength(100)]
    public string? PaymentMethod { get; set; }

    /// <summary>Tiền cọc thực hiện HĐ (đã quy đổi nếu nhập %).</summary>
    public decimal DepositAmount { get; set; }

    /// <summary>% cọc trên giá trị trước VAT — null/0 khi nhập số tiền cố định.</summary>
    public decimal? DepositPercent { get; set; }

    public Guid? PrintTemplateId { get; set; }

    public int Revision { get; set; } = 1;

    [MaxLength(200)]
    public string? QuotedBy { get; set; }

    public Guid? QuotedByEmployeeId { get; set; }

    /// <summary>Tiến độ HĐ / xuất kho / bàn giao / nghiệm thu. Không đụng PosSaleOrder.</summary>
    public PosQuoteCommercialStage CommercialStage { get; set; } = PosQuoteCommercialStage.None;

    public virtual ICollection<PosQuoteLine> Lines { get; set; } = [];
    public virtual ICollection<PosQuoteDocument> Documents { get; set; } = [];
    public virtual ICollection<PosQuoteActivity> Activities { get; set; } = [];
}

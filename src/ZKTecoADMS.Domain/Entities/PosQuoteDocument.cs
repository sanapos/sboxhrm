using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>Chứng từ thương mại gắn báo giá (HĐ, BBBG, nghiệm thu, phiếu xuất).</summary>
public class PosQuoteDocument : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    [Required]
    public Guid QuoteId { get; set; }
    public virtual PosQuote? Quote { get; set; }

    public PosQuoteDocumentKind Kind { get; set; }

    [Required]
    [MaxLength(30)]
    public string DocNo { get; set; } = string.Empty;

    [MaxLength(200)]
    public string Title { get; set; } = string.Empty;

    public string HtmlContent { get; set; } = string.Empty;

    [MaxLength(1000)]
    public string? Note { get; set; }

    public DateTime? IssuedAt { get; set; }

    [MaxLength(200)]
    public string? IssuedBy { get; set; }

    public Guid? PrintTemplateId { get; set; }

    /// <summary>Phiếu xuất kho thật (nếu đã trừ tồn) — không phải đơn bán.</summary>
    public Guid? StockIssueId { get; set; }
}

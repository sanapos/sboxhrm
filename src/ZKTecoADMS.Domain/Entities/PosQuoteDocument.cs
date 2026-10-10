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

    /// <summary>Mẫu in chọn riêng cho chứng từ này (HTML hoặc Word) — null = theo báo giá / mặc định cửa hàng.</summary>
    public Guid? PrintTemplateId { get; set; }

    /// <summary>Đã sửa lời văn riêng — in đúng <see cref="HtmlContent"/>, không dựng lại từ mẫu.</summary>
    public bool IsCustomWording { get; set; }

    /// <summary>
    /// Mẫu riêng của CHỈ chứng từ này (HTML còn trường động {…}): sửa toàn bộ lời văn / bố cục mà số liệu,
    /// hàng hóa, đợt thanh toán vẫn lấy từ báo giá hiện tại. Null = theo mẫu chọn / mẫu chung.
    /// Bản chụp lời văn (<see cref="IsCustomWording"/>) vẫn thắng nếu có.
    /// </summary>
    public string? CustomTemplateHtml { get; set; }

    public DateTime? WordingUpdatedAt { get; set; }

    [MaxLength(200)]
    public string? WordingUpdatedBy { get; set; }

    /// <summary>Dấu số liệu báo giá lúc sửa lời văn — khác hiện tại = bản sửa đã cũ.</summary>
    [MaxLength(64)]
    public string? SourceHash { get; set; }

    /// <summary>Phiếu xuất kho thật (nếu đã trừ tồn) — không phải đơn bán.</summary>
    public Guid? StockIssueId { get; set; }
}

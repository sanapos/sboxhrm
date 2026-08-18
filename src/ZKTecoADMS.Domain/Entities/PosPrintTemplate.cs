using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>Mẫu in POS — HTML có placeholder {Token}.</summary>
public class PosPrintTemplate : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    [Required]
    [MaxLength(120)]
    public string Name { get; set; } = string.Empty;

    public PosPrintDocumentType DocumentType { get; set; } = PosPrintDocumentType.SaleInvoice;

    public PosPrintPaperSize PaperSize { get; set; } = PosPrintPaperSize.K80;

    /// <summary>Nội dung HTML mẫu in (placeholder kiểu KiotViet).</summary>
    public string HtmlContent { get; set; } = string.Empty;

    public bool IsDefault { get; set; }

    public bool IsActive { get; set; } = true;

    public int SortOrder { get; set; }

    /// <summary>
    /// Id mẫu chung đã clone (nếu có). Sửa bản cửa hàng không đổi catalog.
    /// </summary>
    public Guid? SourceCatalogId { get; set; }
}

using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Mẫu in chung (soạn sẵn, dùng chung mọi cửa hàng).
/// Cửa hàng «chọn dùng» → clone sang <see cref="PosPrintTemplate"/> của store rồi tùy chỉnh riêng.
/// </summary>
public class PosPrintTemplateCatalog : AuditableEntity<Guid>
{
    [Required]
    [MaxLength(120)]
    public string Name { get; set; } = string.Empty;

    public PosPrintDocumentType DocumentType { get; set; } = PosPrintDocumentType.SaleInvoice;

    public PosPrintPaperSize PaperSize { get; set; } = PosPrintPaperSize.K80;

    public string HtmlContent { get; set; } = string.Empty;

    /// <summary>Gợi ý chọn mặc định khi cửa hàng adopt lần đầu.</summary>
    public bool IsRecommended { get; set; }

    public bool IsActive { get; set; } = true;

    public int SortOrder { get; set; }
}

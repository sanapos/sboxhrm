using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>Lịch sử nội dung một chứng từ báo giá (trước mỗi lần sửa lời văn / khôi phục / đổi mẫu).</summary>
public class PosQuoteDocumentRevision : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }

    [Required]
    public Guid DocumentId { get; set; }

    public string HtmlContent { get; set; } = string.Empty;

    public bool IsCustomWording { get; set; }

    /// <summary>Mẫu riêng của chứng từ tại thời điểm lưu (null = không có).</summary>
    public string? CustomTemplateHtml { get; set; }

    public Guid? PrintTemplateId { get; set; }

    /// <summary>wording / restore / template / revert.</summary>
    [MaxLength(30)]
    public string Reason { get; set; } = string.Empty;
}

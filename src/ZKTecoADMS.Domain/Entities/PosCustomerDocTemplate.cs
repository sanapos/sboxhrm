using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Mẫu báo giá / hợp đồng / … riêng của MỘT khách: chứng từ mới của khách này tự dùng (số liệu vẫn theo
/// báo giá). Nhận khách theo mã khách, không có thì theo SĐT (báo giá gõ tay). Khách khác không thấy.
/// </summary>
public class PosCustomerDocTemplate : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }

    public Guid? CustomerId { get; set; }

    /// <summary>SĐT chuẩn hoá (chỉ số, 84… → 0…) — nhận khách khi báo giá không gắn mã khách.</summary>
    [MaxLength(20)]
    public string? CustomerPhone { get; set; }

    [MaxLength(200)]
    public string? CustomerName { get; set; }

    public PosQuoteDocumentKind Kind { get; set; }

    /// <summary>HTML mẫu còn trường động {…}.</summary>
    public string HtmlContent { get; set; } = string.Empty;

    /// <summary>Chứng từ đã dùng để lưu mẫu này.</summary>
    public Guid? SourceDocumentId { get; set; }
}

using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>Nhật ký mã yêu cầu của khách QR / online — chống gửi trùng bền vững (qua khởi động lại, nhiều máy chủ).</summary>
public class PosQrRequestLog : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }

    [Required]
    [MaxLength(80)]
    public string RequestId { get; set; } = string.Empty;

    [MaxLength(80)]
    public string? Token { get; set; }

    /// <summary>Kết quả đã trả khách lần đầu (JSON).</summary>
    public string? ResultJson { get; set; }
}

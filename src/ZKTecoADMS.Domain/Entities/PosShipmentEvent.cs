using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Nhật ký hành trình vận đơn: mỗi lần đổi trạng thái (webhook hãng, đồng bộ, thao tác tay)
/// là một dòng — dùng cho báo cáo giao thất bại / hoàn hàng / hủy và tra cứu.
/// </summary>
public class PosShipmentEvent : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }

    [Required]
    public Guid SaleOrderId { get; set; }

    [MaxLength(30)]
    public string? CarrierCode { get; set; }

    [MaxLength(64)]
    public string? TrackingCode { get; set; }

    /// <summary>Mã chuẩn ShipmentStatus (created, delivery_failed, returned…).</summary>
    [MaxLength(30)]
    public string StatusCode { get; set; } = string.Empty;

    /// <summary>Trạng thái gốc của hãng (chữ / số) để đối chiếu.</summary>
    [MaxLength(200)]
    public string? RawStatus { get; set; }

    [MaxLength(500)]
    public string? Reason { get; set; }

    /// <summary>webhook | sync | create | cancel | manual</summary>
    [MaxLength(20)]
    public string Source { get; set; } = "webhook";

    public DateTime OccurredAt { get; set; }
}

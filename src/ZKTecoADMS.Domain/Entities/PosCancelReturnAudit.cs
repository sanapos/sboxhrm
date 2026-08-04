using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Lịch sử hủy món / hủy đơn / trả hàng — đối soát chống gian lận
/// (lý do, trước/sau tạm tính, ai thao tác, thời điểm).
/// </summary>
public class PosCancelReturnAudit : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    /// <summary>KitchenVoid | SaleCancel | SaleReturn</summary>
    [Required, MaxLength(40)]
    public string ActionType { get; set; } = "";

    [MaxLength(80)]
    public string? Reason { get; set; }
    [MaxLength(500)]
    public string? DetailNote { get; set; }

    /// <summary>true = thao tác sau khi đã in / xin tạm tính.</summary>
    public bool AfterProvisionalBill { get; set; }

    public Guid? SaleOrderId { get; set; }
    [MaxLength(40)]
    public string? OrderNo { get; set; }

    public Guid? ResourceSessionId { get; set; }
    public Guid? ServiceResourceId { get; set; }
    [MaxLength(120)]
    public string? ResourceName { get; set; }

    public Guid? ProductId { get; set; }
    [MaxLength(200)]
    public string? ProductName { get; set; }
    [MaxLength(40)]
    public string? UnitName { get; set; }
    public decimal Qty { get; set; }
    public decimal Amount { get; set; }

    public DateTime OccurredAt { get; set; } = DateTime.UtcNow;
    [MaxLength(200)]
    public string? Actor { get; set; }
    [MaxLength(120)]
    public string? DeviceName { get; set; }
}

using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>Đơn bán hàng POS.</summary>
public class PosSaleOrder : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    [Required]
    [MaxLength(30)]
    public string OrderNo { get; set; } = string.Empty;

    public PosSaleOrderStatus Status { get; set; } = PosSaleOrderStatus.Completed;

    public decimal SubTotal { get; set; }
    public decimal Discount { get; set; }
    public decimal Total { get; set; }
    public decimal PaidAmount { get; set; }

    [MaxLength(50)]
    public string PaymentMethod { get; set; } = "Tiền mặt";

    [MaxLength(200)]
    public string? CustomerName { get; set; }

    public Guid? CustomerId { get; set; }
    public virtual PosCustomer? Customer { get; set; }

    public bool IsDelivery { get; set; }

    [MaxLength(500)]
    public string? DeliveryAddress { get; set; }

    [MaxLength(50)]
    public string? DeliveryPhone { get; set; }

    [MaxLength(100)]
    public string? DeliveryPartner { get; set; }

    [MaxLength(50)]
    public string? DeliveryStatus { get; set; }

    public DateTime? DeliveryDate { get; set; }

    [MaxLength(500)]
    public string? Note { get; set; }

    public DateTime? SaleDate { get; set; }

    [MaxLength(200)]
    public string? SoldBy { get; set; }

    [MaxLength(100)]
    public string? SalesChannel { get; set; }

    [MaxLength(100)]
    public string? PriceListName { get; set; }

    public virtual ICollection<PosSaleOrderLine> Lines { get; set; } = [];
}

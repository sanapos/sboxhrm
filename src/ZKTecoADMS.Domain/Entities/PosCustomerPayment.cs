using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>Thu nợ / thanh toán công nợ khách hàng POS.</summary>
public class PosCustomerPayment : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    [Required]
    public Guid CustomerId { get; set; }
    public virtual PosCustomer? Customer { get; set; }

    public Guid? SaleOrderId { get; set; }
    public virtual PosSaleOrder? SaleOrder { get; set; }

    [Required]
    [MaxLength(30)]
    public string PaymentNo { get; set; } = string.Empty;

    public decimal Amount { get; set; }

    [MaxLength(50)]
    public string PaymentMethod { get; set; } = "Tiền mặt";

    public DateTime PaidAt { get; set; }

    [MaxLength(500)]
    public string? Note { get; set; }
}

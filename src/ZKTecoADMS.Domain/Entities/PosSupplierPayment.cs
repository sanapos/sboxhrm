using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>Thanh toán cho nhà cung cấp (gắn phiếu nhập).</summary>
public class PosSupplierPayment : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    [Required]
    public Guid SupplierId { get; set; }
    public virtual PosSupplier? Supplier { get; set; }

    public Guid? StockReceiptId { get; set; }
    public virtual PosStockReceipt? StockReceipt { get; set; }

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

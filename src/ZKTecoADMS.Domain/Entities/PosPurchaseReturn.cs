using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>Phiếu trả hàng nhập (trả NCC).</summary>
public class PosPurchaseReturn : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    [Required]
    [MaxLength(30)]
    public string ReturnNo { get; set; } = string.Empty;

    public Guid? SupplierId { get; set; }
    public virtual PosSupplier? Supplier { get; set; }

    public Guid? SourceReceiptId { get; set; }
    public virtual PosStockReceipt? SourceReceipt { get; set; }

    [MaxLength(500)]
    public string? Note { get; set; }

    public PosPurchaseReturnStatus Status { get; set; } = PosPurchaseReturnStatus.Draft;

    public decimal TotalQty { get; set; }
    public decimal TotalAmount { get; set; }
    public decimal DiscountAmount { get; set; }
    /// <summary>NCC cần trả lại (số tiền NCC nợ shop sau trả hàng).</summary>
    public decimal RefundDue { get; set; }
    /// <summary>NCC đã trả lại tiền.</summary>
    public decimal RefundReceived { get; set; }

    public DateTime? ReturnDate { get; set; }
    public string? ReturnedBy { get; set; }

    public virtual ICollection<PosPurchaseReturnLine> Lines { get; set; } = [];
}

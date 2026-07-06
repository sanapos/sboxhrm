using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>Lô hàng theo dõi HSD — tạo khi nhập kho, dùng cho FEFO (P1+).</summary>
public class PosStockLot : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    [Required]
    public Guid ProductId { get; set; }
    public virtual PosProduct? Product { get; set; }

    public Guid? VariantId { get; set; }
    public virtual PosProductVariant? Variant { get; set; }

    [MaxLength(50)]
    public string? LotNo { get; set; }

    public DateTime? ManufactureDate { get; set; }
    public DateTime? ExpiryDate { get; set; }

    public decimal QtyOnHand { get; set; }
    public decimal UnitCost { get; set; }

    public PosStockLotStatus Status { get; set; } = PosStockLotStatus.Active;

    public Guid? StockReceiptId { get; set; }
    public virtual PosStockReceipt? StockReceipt { get; set; }

    public Guid? StockReceiptLineId { get; set; }
    public virtual PosStockReceiptLine? StockReceiptLine { get; set; }
}

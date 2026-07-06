using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>Thẻ kho / lịch sử biến động tồn kho.</summary>
public class PosStockTransaction : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    [Required]
    public Guid ProductId { get; set; }
    public virtual PosProduct? Product { get; set; }

    public Guid? VariantId { get; set; }
    public virtual PosProductVariant? Variant { get; set; }

    public PosStockTransactionType TransactionType { get; set; }

    /// <summary>Số lượng biến động (dương = nhập, âm = xuất).</summary>
    public decimal QtyChange { get; set; }

    public decimal QtyAfter { get; set; }

    /// <summary>Giá vốn / đơn giá tại thời điểm giao dịch.</summary>
    public decimal? UnitCost { get; set; }

    /// <summary>Giá trị tiền (COGS, hoàn tiền, giá trị nhập...).</summary>
    public decimal? LineAmount { get; set; }

    [MaxLength(50)]
    public string? ReferenceNo { get; set; }

    [MaxLength(500)]
    public string? Note { get; set; }

    public Guid? SaleOrderId { get; set; }
    public virtual PosSaleOrder? SaleOrder { get; set; }

    public Guid? StockReceiptId { get; set; }
    public virtual PosStockReceipt? StockReceipt { get; set; }

    public Guid? StockIssueId { get; set; }
    public virtual PosStockIssue? StockIssue { get; set; }

    public Guid? StockCountId { get; set; }
    public virtual PosStockCount? StockCount { get; set; }

    public Guid? PurchaseReturnId { get; set; }
    public virtual PosPurchaseReturn? PurchaseReturn { get; set; }

    public Guid? LotId { get; set; }
    public virtual PosStockLot? Lot { get; set; }
}

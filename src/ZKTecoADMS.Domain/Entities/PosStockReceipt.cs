using System.ComponentModel.DataAnnotations;

using ZKTecoADMS.Domain.Entities.Base;

using ZKTecoADMS.Domain.Enums;



namespace ZKTecoADMS.Domain.Entities;



/// <summary>Phiếu nhập hàng / nhập kho POS (PN).</summary>

public class PosStockReceipt : AuditableEntity<Guid>

{

    [Required]

    public Guid StoreId { get; set; }

    public virtual Store? Store { get; set; }



    [Required]

    [MaxLength(30)]

    public string ReceiptNo { get; set; } = string.Empty;



    public Guid? SupplierId { get; set; }

    public virtual PosSupplier? Supplier { get; set; }



    [MaxLength(500)]

    public string? Note { get; set; }



    public PosPurchaseReceiptStatus Status { get; set; } = PosPurchaseReceiptStatus.Completed;



    public DateTime? ImportDate { get; set; }



    [MaxLength(200)]

    public string? ImportedBy { get; set; }



    [MaxLength(50)]

    public string? InputInvoiceNo { get; set; }



    [MaxLength(50)]

    public string? PurchaseOrderNo { get; set; }



    public decimal TotalQty { get; set; }

    public decimal TotalCost { get; set; }

    public decimal DiscountAmount { get; set; }

    public decimal PaidAmount { get; set; }

    /// <summary>Giảm giá phiếu nhập theo % (true) hoặc số tiền (false).</summary>
    public bool DiscountIsPercent { get; set; }

    /// <summary>Giá trị người dùng nhập (% hoặc tiền tùy DiscountIsPercent).</summary>
    public decimal DiscountInput { get; set; }

    /// <summary>Tổng VAT các dòng.</summary>
    public decimal TotalVat { get; set; }



    public virtual ICollection<PosStockReceiptLine> Lines { get; set; } = [];

    public virtual ICollection<PosSupplierPayment> Payments { get; set; } = [];



    public decimal GrandTotal => TotalCost + TotalVat - DiscountAmount;

    public decimal BalanceDue => GrandTotal - PaidAmount;

}


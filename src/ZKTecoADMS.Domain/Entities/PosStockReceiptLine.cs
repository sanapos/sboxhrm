using System.ComponentModel.DataAnnotations;

using ZKTecoADMS.Domain.Entities.Base;



namespace ZKTecoADMS.Domain.Entities;



/// <summary>Chi tiết dòng phiếu nhập kho.</summary>

public class PosStockReceiptLine : AuditableEntity<Guid>

{

    [Required]

    public Guid StoreId { get; set; }

    public virtual Store? Store { get; set; }



    [Required]

    public Guid ReceiptId { get; set; }

    public virtual PosStockReceipt? Receipt { get; set; }



    [Required]

    public Guid ProductId { get; set; }

    public virtual PosProduct? Product { get; set; }



    public Guid? VariantId { get; set; }

    public virtual PosProductVariant? Variant { get; set; }



    [Required]

    [MaxLength(500)]

    public string ProductName { get; set; } = string.Empty;



    [MaxLength(50)]

    public string? ProductCode { get; set; }



    [MaxLength(100)]

    public string? UnitName { get; set; }



    public decimal Qty { get; set; }

    public decimal CostPrice { get; set; }

    public decimal DiscountAmount { get; set; }

    public decimal LineTotal { get; set; }

    /// <summary>Thuế VAT đầu vào (%).</summary>
    public decimal VatRate { get; set; }

    /// <summary>Tiền VAT dòng (= LineTotal trước VAT × VatRate / 100).</summary>
    public decimal VatAmount { get; set; }

    /// <summary>Đơn giá nhập đã bao gồm VAT (CostPrice lưu giá chưa thuế).</summary>
    public bool VatIncluded { get; set; }

    /// <summary>Không chịu thuế (KCT).</summary>
    public bool VatExempt { get; set; }



    [MaxLength(500)]

    public string? LineNote { get; set; }

}


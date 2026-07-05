using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>Đăng ký bảo hành theo seri máy khi bán POS.</summary>
public class PosProductWarrantyRegistration : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    [Required]
    public Guid SaleOrderId { get; set; }
    public virtual PosSaleOrder? SaleOrder { get; set; }

    [Required]
    public Guid SaleOrderLineId { get; set; }
    public virtual PosSaleOrderLine? SaleOrderLine { get; set; }

    [Required]
    public Guid ProductId { get; set; }
    public virtual PosProduct? Product { get; set; }

    public Guid? VariantId { get; set; }
    public virtual PosProductVariant? Variant { get; set; }

    public Guid? CustomerId { get; set; }
    public virtual PosCustomer? Customer { get; set; }

    [Required]
    [MaxLength(100)]
    public string SerialNumber { get; set; } = string.Empty;

    [MaxLength(50)]
    public string? Imei { get; set; }

    public int WarrantyMonths { get; set; }

    public DateTime SaleDate { get; set; }

    public DateTime WarrantyExpiry { get; set; }

    public PosWarrantyStatus Status { get; set; } = PosWarrantyStatus.Active;

    [MaxLength(500)]
    public string? Note { get; set; }
}

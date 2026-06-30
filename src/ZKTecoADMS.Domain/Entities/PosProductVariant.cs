using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>Biến thể SKU của hàng hóa (màu, size, …).</summary>
public class PosProductVariant : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    [Required]
    public Guid ProductId { get; set; }
    public virtual PosProduct? Product { get; set; }

    [Required]
    [MaxLength(50)]
    public string SkuCode { get; set; } = string.Empty;

    [MaxLength(50)]
    public string? Barcode { get; set; }

    [Required]
    [MaxLength(500)]
    public string Name { get; set; } = string.Empty;

    /// <summary>JSON map attributeId → value cho hiển thị / tái tạo.</summary>
    [MaxLength(2000)]
    public string? AttributeJson { get; set; }

    public decimal CostPrice { get; set; }
    public decimal BasePrice { get; set; }
    public decimal OnHandQty { get; set; }
}

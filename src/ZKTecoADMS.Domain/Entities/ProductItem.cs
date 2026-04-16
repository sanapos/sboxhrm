using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Sản phẩm - thông số sản phẩm với đơn giá theo nhiều cấp sản lượng
/// </summary>
public class ProductItem : AuditableEntity<Guid>
{
    [Required, MaxLength(50)]
    public string Code { get; set; } = string.Empty;

    [Required, MaxLength(200)]
    public string Name { get; set; } = string.Empty;

    [MaxLength(50)]
    public string? Unit { get; set; }

    [MaxLength(500)]
    public string? Description { get; set; }

    public int SortOrder { get; set; }

    [Required]
    public Guid ProductGroupId { get; set; }
    public virtual ProductGroup ProductGroup { get; set; } = null!;

    public Guid? StoreId { get; set; }
    public virtual Store? Store { get; set; }

    public virtual ICollection<ProductPriceTier> PriceTiers { get; set; } = new List<ProductPriceTier>();
    public virtual ICollection<ProductionEntry> ProductionEntries { get; set; } = new List<ProductionEntry>();
}

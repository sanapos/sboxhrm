using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>Đơn vị quy đổi (hộp, thùng…) — MVP lưu đơn vị cơ bản + mở rộng sau.</summary>
public class PosProductUnit : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    [Required]
    public Guid ProductId { get; set; }
    public virtual PosProduct? Product { get; set; }

    [Required]
    [MaxLength(100)]
    public string UnitName { get; set; } = string.Empty;

    /// <summary>1 unit này = ConversionRate × đơn vị cơ bản.</summary>
    public decimal ConversionRate { get; set; } = 1;

    public decimal BasePrice { get; set; }

    public bool IsDirectSale { get; set; } = true;

    public bool IsBaseUnit { get; set; }
}

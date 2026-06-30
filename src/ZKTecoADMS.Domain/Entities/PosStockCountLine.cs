using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

public class PosStockCountLine : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    [Required]
    public Guid CountId { get; set; }
    public virtual PosStockCount? Count { get; set; }

    [Required]
    public Guid ProductId { get; set; }
    public virtual PosProduct? Product { get; set; }

    public Guid? VariantId { get; set; }
    public virtual PosProductVariant? Variant { get; set; }

    [MaxLength(500)]
    public string ProductName { get; set; } = string.Empty;

    [MaxLength(50)]
    public string? ProductCode { get; set; }

    [MaxLength(100)]
    public string? UnitName { get; set; }

    /// <summary>Giá vốn tại thời điểm kiểm (tính giá trị lệch).</summary>
    public decimal CostPrice { get; set; }

    /// <summary>Tồn hệ thống (đơn vị cơ bản hoặc biến thể).</summary>
    public decimal SystemQty { get; set; }

    /// <summary>Số đếm thực tế (null = chưa kiểm).</summary>
    public decimal? CountedQty { get; set; }

    public bool IsChecked { get; set; }
}

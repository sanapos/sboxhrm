using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Bậc đơn giá sản phẩm - đơn giá thay đổi theo số lượng sản phẩm đạt được
/// Ví dụ: 0-100 sp: 5000đ/sp, 101-200 sp: 6000đ/sp, >200 sp: 7000đ/sp
/// </summary>
public class ProductPriceTier : AuditableEntity<Guid>
{
    [Required]
    public Guid ProductItemId { get; set; }
    public virtual ProductItem ProductItem { get; set; } = null!;

    /// <summary>Số lượng tối thiểu để áp dụng bậc này</summary>
    [Required]
    public int MinQuantity { get; set; }

    /// <summary>Số lượng tối đa của bậc này (null = không giới hạn)</summary>
    public int? MaxQuantity { get; set; }

    /// <summary>Đơn giá cho bậc này</summary>
    [Required]
    public decimal UnitPrice { get; set; }

    public int TierLevel { get; set; } = 1;

    public Guid? StoreId { get; set; }
    public virtual Store? Store { get; set; }
}

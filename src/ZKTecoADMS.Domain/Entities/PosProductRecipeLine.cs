using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Định lượng nguyên vật liệu cho 1 hàng hóa / dịch vụ (công thức bếp).
/// Tách khỏi combo bán — không hiện thành phần trên hóa đơn.
/// </summary>
public class PosProductRecipeLine : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    [Required]
    public Guid ParentProductId { get; set; }
    public virtual PosProduct? ParentProduct { get; set; }

    [Required]
    public Guid ComponentProductId { get; set; }
    public virtual PosProduct? ComponentProduct { get; set; }

    /// <summary>SL NVL / 1 đơn vị món (cho phép lẻ: 0.05 kg).</summary>
    public decimal Qty { get; set; } = 1;
}

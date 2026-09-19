using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>Thành phần trong combo hàng hóa.</summary>
public class PosProductComboLine : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    [Required]
    public Guid ComboProductId { get; set; }
    public virtual PosProduct? ComboProduct { get; set; }

    [Required]
    public Guid ComponentProductId { get; set; }
    public virtual PosProduct? ComponentProduct { get; set; }

    public decimal Qty { get; set; } = 1;

    /// <summary>
    /// Bật: trừ kho thành phần khi bán (như hàng hóa). Tắt: không kho (như dịch vụ).
    /// </summary>
    public bool TrackStock { get; set; } = true;
}

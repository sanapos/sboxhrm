using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>Ca thu ngân — mở/đóng két. Tắt mặc định, bật trong thiết lập POS.</summary>
public class PosCashierShift : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    public DateTime OpenedAt { get; set; }
    public Guid? OpenedByUserId { get; set; }
    [MaxLength(200)]
    public string? OpenedByName { get; set; }
    public decimal OpeningCash { get; set; }

    public DateTime? ClosedAt { get; set; }
    public Guid? ClosedByUserId { get; set; }
    [MaxLength(200)]
    public string? ClosedByName { get; set; }
    public decimal? CountedCash { get; set; }
    public decimal? ExpectedCash { get; set; }
    public decimal? Difference { get; set; }

    [MaxLength(500)]
    public string? Note { get; set; }

    /// <summary>Open | Closed</summary>
    [MaxLength(20)]
    public string Status { get; set; } = "Open";
}

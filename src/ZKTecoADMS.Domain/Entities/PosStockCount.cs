using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>Phiếu kiểm kê tồn POS.</summary>
public class PosStockCount : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    [Required]
    [MaxLength(30)]
    public string CountNo { get; set; } = string.Empty;

    [Required]
    [MaxLength(200)]
    public string Name { get; set; } = string.Empty;

    [MaxLength(500)]
    public string? Note { get; set; }

    public PosStockCountStatus Status { get; set; } = PosStockCountStatus.InProgress;

    public DateTime? CompletedAt { get; set; }

    /// <summary>Người cân bằng kho khi hoàn thành.</summary>
    public string? BalancedBy { get; set; }

    public virtual ICollection<PosStockCountLine> Lines { get; set; } = [];
}

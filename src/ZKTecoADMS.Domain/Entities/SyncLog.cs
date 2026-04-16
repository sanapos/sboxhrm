using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

public class SyncLog : Entity<Guid>
{
    public Guid DeviceId { get; set; }

    [Required]
    [MaxLength(50)]
    public string SyncType { get; set; } = string.Empty;

    [Required]
    [MaxLength(10)]
    public string Direction { get; set; } = string.Empty;

    public string? RequestData { get; set; }
    public string? ResponseData { get; set; }

    public bool IsSuccess { get; set; } = true;

    [MaxLength(500)]
    public string? ErrorMessage { get; set; }

    public int? DurationMs { get; set; }

    // Navigation Properties
    public virtual Device Device { get; set; } = null!;
}
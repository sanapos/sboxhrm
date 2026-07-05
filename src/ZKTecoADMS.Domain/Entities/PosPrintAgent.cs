using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>Thiết bị mobile làm Print Agent (bridge BT → cloud).</summary>
public class PosPrintAgent : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    [Required]
    [MaxLength(128)]
    public string DeviceId { get; set; } = string.Empty;

    [MaxLength(200)]
    public string? DeviceName { get; set; }

    [MaxLength(200)]
    public string? EmployeeName { get; set; }

    [MaxLength(450)]
    public string? UserId { get; set; }

    /// <summary>JSON array of printer IDs this agent serves.</summary>
    public string AssignedPrinterIdsJson { get; set; } = "[]";

    public bool IsOnline { get; set; }

    public DateTime? LastHeartbeatAt { get; set; }

    [MaxLength(32)]
    public string? AppVersion { get; set; }
}

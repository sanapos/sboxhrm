using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Domain.Entities;
// ZKTecoADMS.Domain/Entities/DeviceCommand.cs
public class DeviceCommand : Entity<Guid>
{
    public Guid DeviceId { get; set; }

    public long CommandId { get; set; } = DateTime.Now.Ticks;

    [Required]
    [MaxLength(1000)]
    public string Command { get; set; } = string.Empty;

    public int Priority { get; set; } = 1;

    [MaxLength(20)]
    public CommandStatus Status { get; set; } = CommandStatus.Created;
    
    public string? ResponseData { get; set; }

    [MaxLength(500)]
    public string? ErrorMessage { get; set; }
    
    public int? Return { get; set; }
    
    public DateTime? SentAt { get; set; }
    
    public DateTime? CompletedAt { get; set; }
    
    public DeviceCommandTypes CommandType { get; set; }
    
    public Guid ObjectReferenceId { get; set; }

    // Navigation Properties
    public virtual Device Device { get; set; } = null!;
}
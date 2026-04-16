using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

// ZKTecoADMS.Domain/Entities/FingerprintTemplate.cs
public class FingerprintTemplate : Entity<Guid>
{
    public Guid EmployeeId { get; set; }
    public int FingerIndex { get; set; }

    [Required]
    public string Template { get; set; } = string.Empty;

    public int? TemplateSize { get; set; }
    public int? Quality { get; set; }
    public int Version { get; set; } = 10;

    // Navigation Properties
    public virtual DeviceUser Employee { get; set; } = null!;
}
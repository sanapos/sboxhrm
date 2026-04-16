using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Domain.Entities;

// ZKTecoADMS.Domain/Entities/Employee.cs
public class DeviceUser : AuditableEntity<Guid>
{
    [Required]
    [MaxLength(20)]
    public string Pin { get; set; } = string.Empty;

    [Required]
    [MaxLength(200)]
    public string Name { get; set; } = string.Empty;

    [MaxLength(50)]
    public string? CardNumber { get; set; }

    [MaxLength(50)]
    public string? Password { get; set; }

    public int GroupId { get; set; } = 1;
    public int Privilege { get; set; }
    public int VerifyMode { get; set; }

    public Guid DeviceId { get; set; }
    public virtual Device Device { get; set; } = null!;

    public Guid? EmployeeId {get;set;}
    public virtual Employee? Employee {get;set;}
    
    // Navigation Properties
    public virtual ICollection<FingerprintTemplate> FingerprintTemplates { get; set; } = new List<FingerprintTemplate>();
    public virtual ICollection<FaceTemplate> FaceTemplates { get; set; } = new List<FaceTemplate>();
    public virtual ICollection<Attendance> AttendanceLogs { get; set; } = new List<Attendance>();
}


using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Face registration for mobile attendance verification.
/// </summary>
public class MobileFaceRegistration : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    [Required]
    [MaxLength(100)]
    public string OdooEmployeeId { get; set; } = string.Empty;

    [Required]
    [MaxLength(200)]
    public string EmployeeName { get; set; } = string.Empty;

    [MaxLength(50)]
    public string? EmployeeCode { get; set; }

    [MaxLength(200)]
    public string? Department { get; set; }

    /// <summary>
    /// JSON array of image URLs stored on server
    /// </summary>
    public string FaceImagesJson { get; set; } = "[]";

    public bool IsVerified { get; set; }

    public DateTime? RegisteredAt { get; set; }

    public DateTime? LastVerifiedAt { get; set; }
}

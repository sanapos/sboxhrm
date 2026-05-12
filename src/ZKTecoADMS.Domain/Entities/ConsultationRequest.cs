using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

public class ConsultationRequest : AuditableEntity<Guid>
{
    [Required]
    [MaxLength(150)]
    public string Name { get; set; } = string.Empty;

    [Required]
    [MaxLength(30)]
    public string Phone { get; set; } = string.Empty;

    [Required]
    [MaxLength(30)]
    public string NormalizedPhone { get; set; } = string.Empty;

    [MaxLength(200)]
    public string? Company { get; set; }

    [MaxLength(120)]
    public string? Province { get; set; }

    [MaxLength(100)]
    public string? InterestedPlan { get; set; }

    [MaxLength(30)]
    public string Status { get; set; } = "New";

    [MaxLength(50)]
    public string Source { get; set; } = "LandingPage";

    [MaxLength(1000)]
    public string? Notes { get; set; }

    [MaxLength(1000)]
    public string? AdminNote { get; set; }

    [MaxLength(100)]
    public string? ClientIp { get; set; }

    [MaxLength(500)]
    public string? UserAgent { get; set; }

    public Guid? StoreId { get; set; }
    public virtual Store? Store { get; set; }
}
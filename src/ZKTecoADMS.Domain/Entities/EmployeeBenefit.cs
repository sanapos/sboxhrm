using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Domain.Entities;

public class EmployeeBenefit : AuditableEntity<Guid>
{
    [Required]
    public Guid EmployeeId { get; set; }
    public Employee Employee { get; set; } = null!;

    [Required]
    public Guid BenefitId { get; set; }
    public Benefit Benefit { get; set; } = null!;

    [Required]
    public DateTime EffectiveDate { get; set; }

    public DateTime? EndDate { get; set; }

    [MaxLength(500)]
    public string? Notes { get; set; }

    public decimal? BalancedPaidLeaveDays { get; set; }

    public decimal? BalancedUnpaidLeaveDays { get; set; }

}

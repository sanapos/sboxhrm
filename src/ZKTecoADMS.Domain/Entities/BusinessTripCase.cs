using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>Hồ sơ công tác — gom ứng trước + hoạch toán + quyết toán.</summary>
public class BusinessTripCase : AuditableEntity<Guid>
{
    [Required]
    [MaxLength(30)]
    public string CaseCode { get; set; } = string.Empty;

    public Guid? EmployeeId { get; set; }
    public virtual Employee? Employee { get; set; }

    public Guid? EmployeeUserId { get; set; }
    public virtual ApplicationUser? EmployeeUser { get; set; }

    public Guid? StoreId { get; set; }
    public virtual Store? Store { get; set; }

    [Required]
    [MaxLength(300)]
    public string Title { get; set; } = string.Empty;

    [MaxLength(300)]
    public string? Destination { get; set; }

    public DateTime? TripFromDate { get; set; }
    public DateTime? TripToDate { get; set; }

    [MaxLength(1000)]
    public string? Note { get; set; }

    public BusinessTripCaseStatus Status { get; set; } = BusinessTripCaseStatus.Draft;

    public decimal AdvanceAmount { get; set; }
    public decimal SettledAmount { get; set; }
    public decimal BalanceAmount { get; set; }

    public virtual BusinessTripAdvanceClaim? AdvanceClaim { get; set; }
    public virtual BusinessTripSettlementClaim? SettlementClaim { get; set; }
}

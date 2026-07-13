using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Domain.Entities;

public class BusinessTripAdvanceClaim : AuditableEntity<Guid>
{
    [Required]
    public Guid CaseId { get; set; }
    public virtual BusinessTripCase? Case { get; set; }

    public Guid? StoreId { get; set; }

    [Required]
    public decimal Amount { get; set; }

    [Required]
    [MaxLength(1000)]
    public string Reason { get; set; } = string.Empty;

    [MaxLength(500)]
    public string? Note { get; set; }

    public DateTime RequestDate { get; set; } = DateTime.UtcNow;

    public AdvanceRequestStatus Status { get; set; } = AdvanceRequestStatus.Pending;

    public Guid? ApprovedById { get; set; }
    public DateTime? ApprovedDate { get; set; }

    [MaxLength(500)]
    public string? RejectionReason { get; set; }

    public bool IsPaid { get; set; }
    [MaxLength(50)]
    public string? PaymentMethod { get; set; }
    public DateTime? PaidDate { get; set; }

    public Guid? CashTransactionId { get; set; }

    public int TotalApprovalLevels { get; set; } = 1;
    public int CurrentApprovalStep { get; set; }

    public virtual ICollection<BusinessTripAdvanceApprovalRecord> ApprovalRecords { get; set; } = [];
}

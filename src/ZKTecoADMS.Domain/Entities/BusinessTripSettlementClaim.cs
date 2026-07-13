using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Domain.Entities;

public class BusinessTripSettlementClaim : AuditableEntity<Guid>
{
    [Required]
    public Guid CaseId { get; set; }
    public virtual BusinessTripCase? Case { get; set; }

    public Guid? StoreId { get; set; }

    public decimal AdvanceAmount { get; set; }
    public decimal TotalAmount { get; set; }
    public decimal TotalWithInvoice { get; set; }
    public decimal TotalWithoutInvoice { get; set; }
    public decimal BalanceAmount { get; set; }

    public BusinessTripSettlementType SettlementType { get; set; } = BusinessTripSettlementType.Balanced;

    [MaxLength(1000)]
    public string? Note { get; set; }

    public DateTime? SubmittedAt { get; set; }

    public AdvanceRequestStatus Status { get; set; } = AdvanceRequestStatus.Pending;

    public Guid? ApprovedById { get; set; }
    public DateTime? ApprovedDate { get; set; }

    [MaxLength(500)]
    public string? RejectionReason { get; set; }

    public bool IsExtraPaid { get; set; }
    [MaxLength(50)]
    public string? ExtraPaymentMethod { get; set; }
    public DateTime? ExtraPaidDate { get; set; }

    public Guid? ExtraCashTransactionId { get; set; }
    public Guid? SurplusPaymentTransactionId { get; set; }
    /// <summary>AdvanceRequest tạo từ dư ứng công tác (trừ lương).</summary>
    public Guid? SurplusAdvanceRequestId { get; set; }

    public int TotalApprovalLevels { get; set; } = 1;
    public int CurrentApprovalStep { get; set; }

    public virtual ICollection<BusinessTripExpenseLine> Lines { get; set; } = [];
    public virtual ICollection<BusinessTripSettlementApprovalRecord> ApprovalRecords { get; set; } = [];
}

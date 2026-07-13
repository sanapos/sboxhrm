using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

public class BusinessTripExpenseLine : AuditableEntity<Guid>
{
    [Required]
    public Guid SettlementClaimId { get; set; }
    public virtual BusinessTripSettlementClaim? SettlementClaim { get; set; }

    public Guid? CategoryId { get; set; }
    public virtual BusinessTripExpenseCategory? Category { get; set; }

    public DateTime ExpenseDate { get; set; }
    public decimal Amount { get; set; }

    [MaxLength(500)]
    public string? Description { get; set; }

    [MaxLength(500)]
    public string? Note { get; set; }

    public bool HasInvoice { get; set; }

    [MaxLength(100)]
    public string? InvoiceNumber { get; set; }
    public DateTime? InvoiceDate { get; set; }

    public int SortOrder { get; set; }

    public virtual ICollection<BusinessTripExpenseAttachment> Attachments { get; set; } = [];
}

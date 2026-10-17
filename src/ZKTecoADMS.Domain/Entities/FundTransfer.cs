using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Chuyển quỹ nội bộ (tiền mặt ↔ ngân hàng, TK ↔ TK). Không tính vào thu/chi.
/// </summary>
public class FundTransfer : AuditableEntity<Guid>, IBranchScoped
{
    [Required]
    [MaxLength(50)]
    public string TransferCode { get; set; } = string.Empty;

    /// <summary>Quỹ nguồn — null = tiền mặt.</summary>
    public Guid? FromBankAccountId { get; set; }

    /// <summary>Quỹ đích — null = tiền mặt.</summary>
    public Guid? ToBankAccountId { get; set; }

    [Required]
    public decimal Amount { get; set; }

    [Required]
    public DateTime TransferDate { get; set; } = DateTime.UtcNow;

    [Required]
    [MaxLength(500)]
    public string Description { get; set; } = string.Empty;

    [MaxLength(1000)]
    public string? InternalNote { get; set; }

    public Guid? StoreId { get; set; }
    public virtual Store? Store { get; set; }

    /// <summary>Chi nhánh của phiếu chuyển quỹ (null = trụ sở).</summary>
    public Guid? BranchId { get; set; }

    public Guid CreatedByUserId { get; set; }
    public virtual ApplicationUser CreatedByUser { get; set; } = null!;

    public virtual BankAccount? FromBankAccount { get; set; }
    public virtual BankAccount? ToBankAccount { get; set; }
}

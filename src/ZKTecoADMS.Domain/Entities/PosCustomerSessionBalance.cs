using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>Số dư buổi / session pack của khách (gym).</summary>
public class PosCustomerSessionBalance : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    [Required]
    public Guid CustomerId { get; set; }
    public virtual PosCustomer? Customer { get; set; }

    /// <summary>Sản phẩm gói buổi nguồn (có thể null nếu adjust tay).</summary>
    public Guid? ProductId { get; set; }
    public virtual PosProduct? Product { get; set; }

    [MaxLength(200)]
    public string PackageName { get; set; } = string.Empty;

    public int TotalSessions { get; set; }
    public int RemainingSessions { get; set; }

    public DateTime? ExpiresAt { get; set; }

    public virtual ICollection<PosCustomerSessionTransaction> Transactions { get; set; } = [];
}

/// <summary>Sổ cái mua / trừ buổi.</summary>
public class PosCustomerSessionTransaction : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    [Required]
    public Guid BalanceId { get; set; }
    public virtual PosCustomerSessionBalance? Balance { get; set; }

    public Guid? CustomerId { get; set; }
    public Guid? SaleOrderId { get; set; }

    public PosSessionTxnType TransactionType { get; set; }

    /// <summary>Dương = cộng, âm = trừ.</summary>
    public int SessionDelta { get; set; }

    public int RemainingAfter { get; set; }

    [MaxLength(500)]
    public string? Note { get; set; }
}

using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>Số lượt nhận thông báo chuyển khoản còn lại của cửa hàng (độc lập Point CRM).</summary>
public class PosStoreNotificationCredit : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    public int RemainingCount { get; set; }

    public int TotalGranted { get; set; }

    public int TotalConsumed { get; set; }
}

/// <summary>Gói bán lượt thông báo (SuperAdmin).</summary>
public class PosNotificationCreditPackage : AuditableEntity<Guid>
{
    [Required]
    [MaxLength(120)]
    public string Name { get; set; } = string.Empty;

    public int CreditCount { get; set; }

    public decimal Price { get; set; }

    public bool IsActive { get; set; } = true;

    public bool IsPublic { get; set; } = true;

    [MaxLength(500)]
    public string? Description { get; set; }

    public int SortOrder { get; set; }
}

/// <summary>Đơn mua gói lượt thông báo.</summary>
public class PosNotificationCreditPurchase : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    public Guid? PackageId { get; set; }
    public virtual PosNotificationCreditPackage? Package { get; set; }

    public int CreditCount { get; set; }

    public decimal AmountPaid { get; set; }

    public PosNotificationCreditPurchaseStatus Status { get; set; } =
        PosNotificationCreditPurchaseStatus.Pending;

    [MaxLength(120)]
    public string? ExternalPaymentRef { get; set; }

    public DateTime? PaidAt { get; set; }

    [MaxLength(500)]
    public string? Note { get; set; }
}

/// <summary>Sổ cái cộng/trừ lượt thông báo — idempotency qua ProviderTransactionCode.</summary>
public class PosNotificationCreditLedger : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    /// <summary>Dương = cộng, âm = trừ.</summary>
    public int Delta { get; set; }

    public int BalanceAfter { get; set; }

    public PosNotificationCreditLedgerSource Source { get; set; }

    public Guid? ReferenceId { get; set; }

    /// <summary>Mã giao dịch cổng (unique khi Source = WebhookConsume).</summary>
    [MaxLength(120)]
    public string? ProviderTransactionCode { get; set; }

    public PosPaymentNotifyProvider? Provider { get; set; }

    [MaxLength(500)]
    public string? Note { get; set; }
}

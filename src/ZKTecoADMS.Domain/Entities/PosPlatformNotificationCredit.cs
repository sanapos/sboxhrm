using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>Kho lượt thông báo CK tập trung của Sbox (mua từ Tingee, bán lại cửa hàng).</summary>
public class PosPlatformNotificationCredit : AuditableEntity<Guid>
{
    public int RemainingCount { get; set; }

    /// <summary>Tổng lượt đã nạp từ Tingee / SuperAdmin.</summary>
    public int TotalPurchased { get; set; }

    /// <summary>Tổng lượt đã cấp cho cửa hàng.</summary>
    public int TotalAllocated { get; set; }

    /// <summary>Giá vốn gần nhất (đ/lượt) khi nạp kho.</summary>
    public decimal LastCostPerCredit { get; set; }
}

public class PosPlatformNotificationCreditLedger : AuditableEntity<Guid>
{
    public int Delta { get; set; }

    public int BalanceAfter { get; set; }

    public PosPlatformCreditLedgerSource Source { get; set; }

    public Guid? StoreId { get; set; }

    public Guid? ReferenceId { get; set; }

    [MaxLength(500)]
    public string? Note { get; set; }
}

/// <summary>Credentials Tingee master của Sbox (SuperAdmin).</summary>
public class PosPlatformTingeeSetting : AuditableEntity<Guid>
{
    public bool TingeeEnabled { get; set; }

    [MaxLength(100)]
    public string? TingeeClientId { get; set; }

    [MaxLength(300)]
    public string? TingeeSecretKey { get; set; }

    [MaxLength(300)]
    public string? TingeeWebhookSecret { get; set; }

    /// <summary>UAT hoặc Production.</summary>
    [MaxLength(20)]
    public string ApiEnvironment { get; set; } = "Production";

    [MaxLength(200)]
    public string? ApiBaseUrlOverride { get; set; }

    /// <summary>VA mặc định nhận CK mua gói credit (tuỳ chọn).</summary>
    [MaxLength(100)]
    public string? DefaultVaAccountNumber { get; set; }
}

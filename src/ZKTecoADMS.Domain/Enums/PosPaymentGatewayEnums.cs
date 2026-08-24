namespace ZKTecoADMS.Domain.Enums;

/// <summary>Cổng / phương thức xác nhận chuyển khoản tự động.</summary>
public enum PosPaymentNotifyProvider
{
    /// <summary>VietQR tĩnh — thu ngân tự xác nhận, không trừ credit thông báo.</summary>
    VietQr = 0,

    /// <summary>Tingee — webhook xác nhận tự động, trừ 1 credit/lần.</summary>
    Tingee = 1,
}

public enum PosTransferPaymentIntentStatus
{
    Waiting = 0,
    Confirmed = 1,
    Completed = 2,
    Expired = 3,
    Cancelled = 4,
}

public enum PosNotificationCreditLedgerSource
{
    Purchase = 0,
    WebhookConsume = 1,
    AdminGrant = 2,
    AdminAdjust = 3,
    Refund = 4,
}

public enum PosNotificationCreditPurchaseStatus
{
    Pending = 0,
    Paid = 1,
    Cancelled = 2,
    Failed = 3,
}

public enum PosPlatformCreditLedgerSource
{
    /// <summary>SuperAdmin nạp kho (mua gói Tingee).</summary>
    TingeePurchase = 0,

    /// <summary>Cấp/bán cho cửa hàng.</summary>
    StoreAllocation = 1,

    AdminAdjust = 2,
}

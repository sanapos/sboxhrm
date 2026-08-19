using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>Đơn chờ / đã xác nhận chuyển khoản (Tingee webhook hoặc thủ công).</summary>
public class PosTransferPaymentIntent : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    public Guid? SaleOrderId { get; set; }
    public virtual PosSaleOrder? SaleOrder { get; set; }

    /// <summary>Mã đơn gửi sang cổng (orderId Tingee).</summary>
    [Required]
    [MaxLength(100)]
    public string ExternalOrderId { get; set; } = string.Empty;

    [MaxLength(40)]
    public string? OrderNo { get; set; }

    /// <summary>Chỉ hiển thị — không dùng tính credit.</summary>
    public decimal AmountExpected { get; set; }

    public PosPaymentNotifyProvider Provider { get; set; } = PosPaymentNotifyProvider.Tingee;

    public PosTransferPaymentIntentStatus Status { get; set; } =
        PosTransferPaymentIntentStatus.Waiting;

    [MaxLength(120)]
    public string? ProviderTransactionCode { get; set; }

    [MaxLength(500)]
    public string? TransferContent { get; set; }

    public DateTime? ConfirmedAt { get; set; }

    public DateTime? CompletedAt { get; set; }

    public DateTime ExpiresAt { get; set; }

    [MaxLength(200)]
    public string? TableName { get; set; }

    [MaxLength(2000)]
    public string? RawWebhookJson { get; set; }
}

/// <summary>Audit webhook nhận từ cổng thanh toán.</summary>
public class PosPaymentWebhookEvent : AuditableEntity<Guid>
{
    public Guid? StoreId { get; set; }

    public PosPaymentNotifyProvider Provider { get; set; }

    [MaxLength(120)]
    public string? ProviderTransactionCode { get; set; }

    [MaxLength(80)]
    public string? EventType { get; set; }

    public bool SignatureValid { get; set; }

    [MaxLength(10)]
    public string? ResultCode { get; set; }

    public Guid? TransferIntentId { get; set; }

    [MaxLength(8000)]
    public string? PayloadJson { get; set; }

    public DateTime ReceivedAt { get; set; } = DateTime.UtcNow;
}

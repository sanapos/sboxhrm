using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>Cấu hình xác nhận chuyển khoản theo cửa hàng (Tingee, cổng khác sau).</summary>
public class PosPaymentGatewaySetting : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    /// <summary>Chế độ mặc định khi thu ngân chọn CK: VietQR (thủ công) hoặc Tingee (tự động).</summary>
    public PosPaymentNotifyProvider DefaultTransferProvider { get; set; } = PosPaymentNotifyProvider.VietQr;

    public bool TingeeEnabled { get; set; }

    [MaxLength(100)]
    public string? TingeeClientId { get; set; }

    [MaxLength(300)]
    public string? TingeeSecretKey { get; set; }

    [MaxLength(100)]
    public string? TingeeVaAccountNumber { get; set; }

    [MaxLength(50)]
    public string? TingeeMerchantId { get; set; }

    /// <summary>Secret verify webhook IPN (HMAC SHA512).</summary>
    [MaxLength(300)]
    public string? TingeeWebhookSecret { get; set; }

    /// <summary>JSON mở rộng cho provider khác (Momo, VNPay…).</summary>
    [MaxLength(4000)]
    public string? ExtraJson { get; set; }
}

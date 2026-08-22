using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Cấu hình API đơn vị giao hàng theo cửa hàng.
/// Một dòng / (StoreId, CarrierCode): Ghn | Ghtk | ViettelPost | Ahamove.
/// </summary>
public class PosShippingCarrierSetting : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    /// <summary>Ghn | Ghtk | ViettelPost | Ahamove</summary>
    [Required]
    [MaxLength(30)]
    public string CarrierCode { get; set; } = string.Empty;

    public bool Enabled { get; set; }

    public bool UseSandbox { get; set; }

    /// <summary>Token / API key (GHN, GHTK, AhaMove). Viettel: token cache sau login.</summary>
    [MaxLength(2000)]
    public string? ApiToken { get; set; }

    /// <summary>GHN ShopId; AhaMove mobile/account; GHTK partner code (X-Client-Source).</summary>
    [MaxLength(100)]
    public string? ShopId { get; set; }

    [MaxLength(100)]
    public string? Username { get; set; }

    [MaxLength(200)]
    public string? Password { get; set; }

    /// <summary>Ghi đè base URL nếu cần (mặc định theo carrier + sandbox).</summary>
    [MaxLength(300)]
    public string? ApiBaseUrl { get; set; }

    [MaxLength(120)]
    public string? PickupName { get; set; }

    [MaxLength(30)]
    public string? PickupPhone { get; set; }

    [MaxLength(500)]
    public string? PickupAddress { get; set; }

    [MaxLength(100)]
    public string? FromProvinceName { get; set; }

    [MaxLength(100)]
    public string? FromDistrictName { get; set; }

    [MaxLength(100)]
    public string? FromWardName { get; set; }

    /// <summary>GHN district id / Viettel province id…</summary>
    [MaxLength(40)]
    public string? FromDistrictId { get; set; }

    [MaxLength(40)]
    public string? FromWardCode { get; set; }

    [MaxLength(40)]
    public string? FromProvinceId { get; set; }

    /// <summary>JSON mở rộng (service_id mặc định, tip AhaMove…).</summary>
    [MaxLength(4000)]
    public string? ExtraJson { get; set; }
}

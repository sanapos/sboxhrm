using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>Thiết bị đã từng đăng nhập vào cửa hàng (web / mobile / POS) — đếm theo gói MaxAccessDevices.</summary>
public class StoreAccessDevice : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    public Guid? UserId { get; set; }

    [Required]
    [MaxLength(80)]
    public string DeviceKey { get; set; } = string.Empty;

    [Required]
    [MaxLength(20)]
    public string Platform { get; set; } = "web";

    [MaxLength(200)]
    public string? DeviceName { get; set; }

    public DateTime LastSeenAt { get; set; } = DateTime.UtcNow;
}

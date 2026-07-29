using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>Thiết lập bán hàng theo ngành — 1 bản ghi / cửa hàng.</summary>
public class PosStoreSellSettings : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    public PosSellProfile SellProfile { get; set; } = PosSellProfile.Retail;

    /// <summary>quick | normal | delivery</summary>
    [MaxLength(20)]
    public string DefaultSellMode { get; set; } = "quick";

    public bool EnableResources { get; set; }
    public bool EnableHourlyBilling { get; set; }
    public bool EnableSessionPacks { get; set; }
    public bool RequireResourceOnSale { get; set; }
    public bool ShowFloorPlan { get; set; }

    /// <summary>Cho phép in hóa đơn tạm tính từ màn thanh toán.</summary>
    public bool AllowProvisionalBill { get; set; }

    /// <summary>
    /// Khóa draft / «Lấy quyền» giữa nhiều máy POS.
    /// Tắt khi cửa hàng chỉ dùng 1 máy — tránh dialog và heartbeat thừa.
    /// </summary>
    public bool EnableMultiDeviceDraftLock { get; set; }

    /// <summary>Hỏi số khách khi mở bàn trống trên sơ đồ.</summary>
    public bool PromptGuestCountOnOpen { get; set; }

    /// <summary>JSON flags mở rộng (tùy ngành).</summary>
    [MaxLength(4000)]
    public string? ExtraJson { get; set; }
}

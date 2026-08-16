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

    /// <summary>
    /// Cho phép bán khi tồn khả dụng &lt; 0 (OnHand có thể âm sau trừ).
    /// Tắt (mặc định): chặn thanh toán nếu không đủ tồn.
    /// </summary>
    public bool AllowNegativeStock { get; set; }

    /// <summary>
    /// Giờ bắt đầu ngày kinh doanh VN (0–23) cho báo cáo / cuối ngày.
    /// 0 = nửa đêm lịch (vẫn quy đổi UTC+7). &gt;0 = ngày qua đêm (vd. 6 = 06:00→06:00 hôm sau).
    /// </summary>
    public int ReportDayStartHour { get; set; }

    /// <summary>
    /// Ca thu ngân (mở ca / đóng ca / đếm két). Tắt mặc định — bật trong thiết lập khi cửa hàng cần.
    /// </summary>
    public bool EnableCashierShift { get; set; }

    /// <summary>
    /// QR order tại bàn — khách quét QR gọi món. Tắt mặc định.
    /// </summary>
    public bool EnableQrTableOrder { get; set; }

    /// <summary>
    /// QR order: tự enqueue phiếu bếp khi khách gửi món. Tắt = thu ngân in thủ công (Báo bếp).
    /// Mặc định bật (giữ hành vi v1).
    /// </summary>
    public bool EnableQrOrderAutoPrint { get; set; } = true;

    /// <summary>SP dịch vụ tính giờ mặc định khi mở bàn (RoomHourly / salon).</summary>
    public Guid? DefaultHourlyProductId { get; set; }
    public virtual PosProduct? DefaultHourlyProduct { get; set; }

    /// <summary>JSON flags mở rộng (tùy ngành).</summary>
    [MaxLength(4000)]
    public string? ExtraJson { get; set; }
}

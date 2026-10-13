using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Số liệu mạng của 1 thiết bị POS trong 1 khung 5 phút (giờ UTC, mốc chia hết 5 phút).
/// App gom tại máy, mất mạng thì giữ lại gửi sau — nhờ vậy báo cáo thấy được cả lúc mất mạng.
/// Dùng cho báo cáo «Mạng cửa hàng» (có đủ ổn định để order / in qua mạng không). Giữ 35 ngày.
/// </summary>
public class PosNetworkSample : Entity<Guid>
{
    public Guid StoreId { get; set; }

    [MaxLength(128)]
    public string DeviceId { get; set; } = string.Empty;

    [MaxLength(200)]
    public string? DeviceName { get; set; }

    /// <summary>android / ios / web / windows…</summary>
    [MaxLength(16)]
    public string? Platform { get; set; }

    [MaxLength(32)]
    public string? AppVersion { get; set; }

    /// <summary>Thiết bị đang chạy Print Agent (máy giữ máy in cho máy khác in qua).</summary>
    public bool IsAgent { get; set; }

    public DateTime BucketStart { get; set; }

    /// <summary>wifi / ethernet / mobile / none / unknown.</summary>
    [MaxLength(16)]
    public string? ConnType { get; set; }

    /// <summary>Cường độ Wi‑Fi trung bình (dBm), null nếu không đo được.</summary>
    public int? WifiRssi { get; set; }

    public int ApiCalls { get; set; }
    public int ApiErrors { get; set; }
    public int ApiTimeouts { get; set; }

    public int PingSent { get; set; }
    public int PingFailed { get; set; }
    public int? PingP50Ms { get; set; }
    public int? PingP95Ms { get; set; }
    public int? PingMaxMs { get; set; }

    /// <summary>Số giây không gọi được server (ping lỗi liên tiếp).</summary>
    public int OfflineSec { get; set; }

    public int RealtimeDisconnects { get; set; }
    public int RealtimeDownSec { get; set; }

    /// <summary>Thử mở cổng máy in LAN nội bộ (mạng trong quán, không cần Internet).</summary>
    public int PrinterChecks { get; set; }
    public int PrinterFailed { get; set; }
    public int? PrinterAvgMs { get; set; }
}

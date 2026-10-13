using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Lịch sử cài app POS theo thiết bị. Mỗi lần cài mới / xóa dữ liệu app sinh mã cài đặt (InstallId) mới;
/// mã thiết bị (DeviceKey — Android ID, giữ qua cài lại) không đổi → server thấy «cài lại» và đối chiếu
/// với số hóa đơn offline đã cấp mà chưa đồng bộ (chống bán offline rồi gỡ app / xóa dữ liệu).
/// </summary>
public class PosDeviceInstall : Entity<Guid>
{
    public Guid StoreId { get; set; }

    [MaxLength(128)]
    public string DeviceKey { get; set; } = string.Empty;

    [MaxLength(64)]
    public string InstallId { get; set; } = string.Empty;

    [MaxLength(200)]
    public string? DeviceName { get; set; }

    [MaxLength(16)]
    public string? Platform { get; set; }

    [MaxLength(32)]
    public string? AppVersion { get; set; }

    /// <summary>Thời điểm cài app theo hệ điều hành (Android PackageInfo.firstInstallTime).</summary>
    public DateTime? OsFirstInstallAt { get; set; }

    public DateTime FirstSeenAt { get; set; }
    public DateTime LastSeenAt { get; set; }

    [MaxLength(200)]
    public string? LastUserName { get; set; }

    /// <summary>Đơn offline còn trên máy chưa gửi (máy tự báo lúc online).</summary>
    public int PendingOfflineSales { get; set; }

    /// <summary>Số offline lớn nhất máy này đã dùng (máy tự báo).</summary>
    public int? LastOfflineSeq { get; set; }
}

/// <summary>
/// Dải số hóa đơn offline cấp trước cho thiết bị (khi còn mạng). Bán offline chỉ dùng số trong dải →
/// số đã cấp mà không bao giờ đồng bộ (gỡ app / xóa dữ liệu) hiện ra trong báo cáo kiểm soát.
/// </summary>
public class PosOfflineSerialBlock : Entity<Guid>
{
    public Guid StoreId { get; set; }

    [MaxLength(128)]
    public string DeviceKey { get; set; } = string.Empty;

    [MaxLength(64)]
    public string InstallId { get; set; } = string.Empty;

    [MaxLength(200)]
    public string? DeviceName { get; set; }

    public int FromSeq { get; set; }
    public int ToSeq { get; set; }

    [MaxLength(200)]
    public string? ReservedBy { get; set; }
}

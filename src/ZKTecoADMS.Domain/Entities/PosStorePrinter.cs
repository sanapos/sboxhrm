using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>Máy in đăng ký theo cửa hàng (LAN/BT/Sunmi).</summary>
public class PosStorePrinter : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    [Required]
    [MaxLength(120)]
    public string Name { get; set; } = string.Empty;

    public PosPrinterConnectionType ConnectionType { get; set; } = PosPrinterConnectionType.Lan;

    [MaxLength(32)]
    public string? PrinterBrand { get; set; }

    [MaxLength(16)]
    public string PaperSize { get; set; } = "K80";

    [MaxLength(32)]
    public string? TextMode { get; set; }

    [MaxLength(64)]
    public string? BluetoothAddress { get; set; }

    [MaxLength(120)]
    public string? BluetoothName { get; set; }

    [MaxLength(64)]
    public string? LanHost { get; set; }

    public int LanPort { get; set; } = 9100;

    [MaxLength(120)]
    public string? UsbDeviceName { get; set; }

    public int FeedBeforeCut { get; set; } = 8;

    public bool PartialCut { get; set; } = true;

    /// <summary>Phiếu bếp: cắt giấy sau từng món (treo/giao từng phần).</summary>
    public bool CutPerItem { get; set; }

    /// <summary>Gửi lệnh mở két khi in hóa đơn (ESC p / SunmiDrawer).</summary>
    public bool OpenCashDrawer { get; set; }

    /// <summary>Chỉ mở két khi thanh toán tiền mặt.</summary>
    public bool OpenDrawerCashOnly { get; set; } = true;

    /// <summary>Gửi lệnh bip loa máy in khi in.</summary>
    public bool BeepOnPrint { get; set; }

    /// <summary>Máy in mặc định cửa hàng khi không có route.</summary>
    public bool IsDefault { get; set; }

    public PosPrinterHealthStatus HealthStatus { get; set; } = PosPrinterHealthStatus.Unknown;

    public DateTime? LastSeenAt { get; set; }

    [MaxLength(500)]
    public string? LastErrorMessage { get; set; }

    /// <summary>BT/USB: cần Print Agent. LAN: in trực tiếp.</summary>
    public bool RequiresAgent { get; set; }

    /// <summary>
    /// Máy in nội bộ trên thiết bị POS (không phải agent cloud).
    /// Vẫn nằm trong danh sách cửa hàng để gán món dùng chung.
    /// </summary>
    public bool IsDeviceLocal { get; set; }

    /// <summary>DeviceId máy POS sở hữu máy in nội bộ (PosDeviceIdentity).</summary>
    [MaxLength(64)]
    public string? OwnerDeviceId { get; set; }

    public int SortOrder { get; set; }

    public virtual ICollection<PosPrinterDocumentRoute> DocumentRoutes { get; set; } = [];
}

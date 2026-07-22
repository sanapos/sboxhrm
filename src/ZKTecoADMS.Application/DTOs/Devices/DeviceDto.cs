namespace ZKTecoADMS.Application.DTOs.Devices;

public class DeviceDto
{
    public Guid Id { get; set; }
    public string SerialNumber { get; set; } = string.Empty;
    public string DeviceName { get; set; } = string.Empty;
    public string Location { get; set; } = string.Empty;
    public DateTime? LastOnline { get; set; }
    public bool IsActive { get; set; }
    public string Description { get; set; } = string.Empty;
    public string DeviceStatus { get; set; } = string.Empty;
    public string? IpAddress { get; set; }

    public Guid? OwnerId { get; set; }
    public bool IsClaimed { get; set; }
    public DateTime? ClaimedAt { get; set; }

    public Guid? StoreId { get; set; }
    public string? StoreName { get; set; }

    public string? EngineProfile { get; set; }
    public string? Platform { get; set; }
    public string? FirmwareVersion { get; set; }
    public bool? SupportsUserQuery { get; set; }
    public bool? SupportsAttendanceQuery { get; set; }
    public bool? SupportsEnrollFingerprint { get; set; }
    public bool? SupportsFaceUpdate { get; set; }
    public bool? SupportsDoorControl { get; set; }
    public bool PreferStampSync { get; set; }
    public bool AllowEnrollFingerprintUi { get; set; } = true;
    /// <summary>True only when device can open remote face capture (e.g. ZAM70 / AndroidVisibleLight).</summary>
    public bool AllowEnrollFaceUi { get; set; }
    /// <summary>False when device learned unsupported door CONTROL DEVICE (-1002).</summary>
    public bool AllowDoorControlUi { get; set; } = true;
    public string? CapabilityNotes { get; set; }
}

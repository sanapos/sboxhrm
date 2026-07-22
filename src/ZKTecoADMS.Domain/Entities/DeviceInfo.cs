using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities
{
    public class DeviceInfo : Entity<Guid>
    {
        public Guid DeviceId { get; set; }

        public Device Device { get; set; } = null!;

        public string? FirmwareVersion { get; set; }

        public int EnrolledUserCount { get; set; }

        public int FingerprintCount { get; set; }

        public int AttendanceCount { get; set; }

        public string? DeviceIp { get; set; }

        public string? FingerprintVersion { get; set; }

        public string? FaceVersion { get; set; }

        public string? FaceTemplateCount { get; set; }

        public string? DevSupportData { get; set; }

        /// <summary>Platform từ options (ZEM600, ZLM60, Android, …).</summary>
        public string? Platform { get; set; }

        /// <summary>PUSH protocol version (pushver query hoặc options).</summary>
        public string? PushVersion { get; set; }

        /// <summary>DeviceName option (khác Device.DeviceName do user đặt).</summary>
        public string? DeviceModelName { get; set; }

        public string? OemVendor { get; set; }

        /// <summary>Default | PullDeny | AndroidVisibleLight | Linux | TftLegacy</summary>
        public string? EngineProfile { get; set; }

        /// <summary>null = chưa xác định (cho phép probe).</summary>
        public bool? SupportsUserQuery { get; set; }

        public bool? SupportsAttendanceQuery { get; set; }

        public bool? SupportsEnrollFingerprint { get; set; }

        public bool? SupportsFaceUpdate { get; set; }

        /// <summary>null = chưa xác định (cho phép thử mở/đóng cửa một lần). false = máy không hỗ trợ CONTROL DEVICE.</summary>
        public bool? SupportsDoorControl { get; set; }

        /// <summary>Khi true: sync dùng Stamp=0 + CHECK thay vì DATA QUERY (tránh -1002).</summary>
        public bool PreferStampSync { get; set; }

        public DateTime? CapabilityUpdatedAt { get; set; }

        public string? CapabilityNotes { get; set; }
    }
}

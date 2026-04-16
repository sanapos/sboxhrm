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

    }
}


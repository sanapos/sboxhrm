using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>Mẫu CPU/RAM máy chủ theo thời gian — Super Admin theo dõi hiệu năng.</summary>
public class ServerMetricSample : Entity<Guid>
{
    public DateTime SampledAt { get; set; } = DateTime.UtcNow;

    /// <summary>0–100. Giá trị âm = không đo được.</summary>
    public double CpuPercent { get; set; }

    /// <summary>0–100. Giá trị âm = không đo được.</summary>
    public double RamPercent { get; set; }

    public long RamUsedMb { get; set; }
    public long RamTotalMb { get; set; }
    public long ProcessWorkingSetMb { get; set; }

    /// <summary>cgroup | proc | windows | process</summary>
    public string Source { get; set; } = "unknown";
}

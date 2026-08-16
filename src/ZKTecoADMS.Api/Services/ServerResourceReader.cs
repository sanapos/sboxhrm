using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;

namespace ZKTecoADMS.Api.Services;

public readonly record struct CpuTick(ulong Idle, ulong Total, string Source = "");

public sealed record ServerMetricsSnapshot(
    DateTime SampledAt,
    double CpuPercent,
    double RamPercent,
    long RamUsedMb,
    long RamTotalMb,
    long ProcessWorkingSetMb,
    string Source,
    int CpuCores = 0,
    double? CpuQuotaCores = null,
    long DiskUsedMb = 0,
    long DiskTotalMb = 0,
    long DiskFreeMb = 0,
    double DiskPercent = -1,
    string DiskMount = "",
    long RamCgroupLimitMb = 0,
    long RamCgroupUsedMb = 0)
{
    public const double AlertThresholdPercent = 70;
    public const double DiskAlertPercent = 90;

    public bool CpuAlert => CpuPercent >= AlertThresholdPercent;
    public bool RamAlert => RamPercent >= AlertThresholdPercent;
    public bool DiskAlert => DiskPercent >= DiskAlertPercent || (DiskTotalMb > 0 && DiskFreeMb < 5 * 1024);
    public bool AnyAlert => CpuAlert || RamAlert || DiskAlert;
}

/// <summary>
/// Đọc CPU/RAM host hoặc cgroup (Docker Linux). Windows dùng kernel32.
/// </summary>
public static class ServerResourceReader
{
    public static long ProcessWorkingSetMb()
    {
        using var p = System.Diagnostics.Process.GetCurrentProcess();
        return p.WorkingSet64 / (1024 * 1024);
    }

    public static bool TryReadRam(out long usedMb, out long totalMb, out double percent, out string source)
    {
        usedMb = 0;
        totalMb = 0;
        percent = -1;
        source = "unknown";

        // Super Admin xem RAM máy chủ (host), không lấy hạn mức Docker 8G.
        if (OperatingSystem.IsLinux() && TryReadProcMem(out usedMb, out totalMb, out percent))
        {
            source = "proc";
            return true;
        }

        if (TryReadCgroupRam(out usedMb, out totalMb, out percent))
        {
            source = "cgroup";
            return true;
        }

        if (OperatingSystem.IsWindows() && TryReadWindowsRam(out usedMb, out totalMb, out percent))
        {
            source = "windows";
            return true;
        }

        var ws = ProcessWorkingSetMb();
        usedMb = ws;
        totalMb = 0;
        percent = -1;
        source = "process";
        return false;
    }

    public static CpuTick ReadCpuTick()
    {
        if (OperatingSystem.IsLinux())
        {
            var proc = ReadProcStat();
            if (proc != null) return proc.Value;
        }

        if (OperatingSystem.IsWindows() && TryReadWindowsCpu(out var idle, out var total))
            return new CpuTick(idle, total, "windows");

        return default;
    }

    public static double CpuPercent(CpuTick a, CpuTick b)
    {
        if (a.Total == 0 || b.Total <= a.Total) return -1;
        var totalDelta = b.Total - a.Total;
        var idleDelta = b.Idle >= a.Idle ? b.Idle - a.Idle : 0;
        if (totalDelta == 0) return -1;
        var busy = 1.0 - (idleDelta / (double)totalDelta);
        return Math.Clamp(busy * 100.0, 0, 100);
    }

    public static async Task<ServerMetricsSnapshot> CaptureAsync(
        CpuTick previous,
        CancellationToken cancellationToken = default)
    {
        CpuTick next;
        if (previous.Total == 0)
        {
            previous = ReadCpuTick();
            await Task.Delay(400, cancellationToken);
            next = ReadCpuTick();
        }
        else
        {
            next = ReadCpuTick();
        }

        TryReadRam(out var usedMb, out var totalMb, out var ramPct, out var ramSource);
        TryReadDisk(out var diskUsed, out var diskTotal, out var diskFree, out var diskPct, out var diskMount);
        long cgroupLimit = 0, cgroupUsed = 0;
        if (TryReadCgroupRam(out var cgUsed, out var cgTotal, out _))
        {
            cgroupUsed = cgUsed;
            cgroupLimit = cgTotal;
        }
        var cpu = CpuPercent(previous, next);
        var source = cpu >= 0 ? (string.IsNullOrEmpty(next.Source) ? ramSource : next.Source) : ramSource;
        return new ServerMetricsSnapshot(
            DateTime.UtcNow,
            cpu,
            ramPct,
            usedMb,
            totalMb,
            ProcessWorkingSetMb(),
            source,
            CpuCoreCount(),
            ReadCpuQuotaCores(),
            diskUsed,
            diskTotal,
            diskFree,
            diskPct,
            diskMount,
            cgroupLimit,
            cgroupUsed);
    }

    public static int CpuCoreCount()
    {
        try
        {
            if (OperatingSystem.IsLinux() && File.Exists("/proc/cpuinfo"))
            {
                var n = File.ReadLines("/proc/cpuinfo")
                    .Count(l => l.StartsWith("processor", StringComparison.Ordinal));
                if (n > 0) return n;
            }
        }
        catch
        {
            // fall through
        }

        return Math.Max(1, Environment.ProcessorCount);
    }

    /// <summary>Giới hạn CPU của container (cgroup), null nếu không giới hạn.</summary>
    public static double? ReadCpuQuotaCores()
    {
        try
        {
            var max = ReadCgroupCpuMax();
            if (max != null) return max;
            var v1 = ReadCgroupCpuQuotaV1();
            if (v1 != null) return v1;
        }
        catch
        {
            // ignore
        }

        return null;
    }

    public static bool TryReadDisk(
        out long usedMb, out long totalMb, out long freeMb, out double percent, out string mount)
    {
        usedMb = 0;
        totalMb = 0;
        freeMb = 0;
        percent = -1;
        mount = "";

        try
        {
            DriveInfo? best = null;
            foreach (var candidate in DiskCandidates())
            {
                try
                {
                    if (!candidate.IsReady || candidate.TotalSize < 1L << 30) continue;
                    if (candidate.DriveType is DriveType.Ram or DriveType.Network) continue;
                    if (best == null || candidate.TotalSize > best.TotalSize)
                        best = candidate;
                }
                catch
                {
                    // skip unreadable mount
                }
            }

            if (best == null) return false;
            totalMb = best.TotalSize / (1024 * 1024);
            freeMb = best.AvailableFreeSpace / (1024 * 1024);
            usedMb = Math.Max(0, totalMb - freeMb);
            if (totalMb <= 0) return false;
            percent = Math.Clamp(usedMb * 100.0 / totalMb, 0, 100);
            mount = string.IsNullOrWhiteSpace(best.Name) ? best.RootDirectory.FullName : best.Name.Trim();
            return true;
        }
        catch
        {
            return false;
        }
    }

    private static IEnumerable<DriveInfo> DiskCandidates()
    {
        if (OperatingSystem.IsLinux())
        {
            foreach (var path in new[] { "/", "/app/wwwroot", "/var/lib/docker", "/data" })
            {
                if (Directory.Exists(path))
                    yield return new DriveInfo(path);
            }
        }

        foreach (var d in DriveInfo.GetDrives())
            yield return d;
    }

    private static double? ReadCgroupCpuMax()
    {
        if (!File.Exists("/sys/fs/cgroup/cpu.max")) return null;
        var parts = File.ReadAllText("/sys/fs/cgroup/cpu.max").Trim()
            .Split(' ', StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length < 2 || parts[0].Equals("max", StringComparison.OrdinalIgnoreCase)) return null;
        if (!double.TryParse(parts[0], NumberStyles.Float, CultureInfo.InvariantCulture, out var quota)) return null;
        if (!double.TryParse(parts[1], NumberStyles.Float, CultureInfo.InvariantCulture, out var period) || period <= 0)
            return null;
        var cores = quota / period;
        return cores > 0 && cores < 256 ? Math.Round(cores, 2) : null;
    }

    private static double? ReadCgroupCpuQuotaV1()
    {
        var quota = ReadLongFile("/sys/fs/cgroup/cpu/cpu.cfs_quota_us");
        var period = ReadLongFile("/sys/fs/cgroup/cpu/cpu.cfs_period_us");
        if (quota == null || period == null || quota <= 0 || period <= 0) return null;
        var cores = quota.Value / (double)period.Value;
        return cores > 0 && cores < 256 ? Math.Round(cores, 2) : null;
    }

    private static bool TryReadCgroupRam(out long usedMb, out long totalMb, out double percent)
    {
        usedMb = 0;
        totalMb = 0;
        percent = -1;
        try
        {
            long? current = ReadLongFile("/sys/fs/cgroup/memory.current")
                            ?? ReadLongFile("/sys/fs/cgroup/memory/memory.usage_in_bytes");
            if (current == null) return false;

            long? max = ReadCgroupMax("/sys/fs/cgroup/memory.max")
                        ?? ReadLongFile("/sys/fs/cgroup/memory/memory.limit_in_bytes");
            if (max == null || max <= 0 || max > 1L << 50)
            {
                if (!TryReadProcMem(out _, out var hostTotal, out _)) return false;
                max = hostTotal * 1024 * 1024;
            }

            usedMb = current.Value / (1024 * 1024);
            totalMb = max.Value / (1024 * 1024);
            if (totalMb <= 0) return false;
            percent = Math.Clamp(usedMb * 100.0 / totalMb, 0, 100);
            return true;
        }
        catch
        {
            return false;
        }
    }

    private static bool TryReadProcMem(out long usedMb, out long totalMb, out double percent)
    {
        usedMb = 0;
        totalMb = 0;
        percent = -1;
        try
        {
            if (!File.Exists("/proc/meminfo")) return false;
            long memTotalKb = 0, memAvailKb = 0;
            foreach (var line in File.ReadLines("/proc/meminfo"))
            {
                if (line.StartsWith("MemTotal:", StringComparison.Ordinal))
                    memTotalKb = ParseKb(line);
                else if (line.StartsWith("MemAvailable:", StringComparison.Ordinal))
                    memAvailKb = ParseKb(line);
            }
            if (memTotalKb <= 0) return false;
            var usedKb = memAvailKb > 0 ? memTotalKb - memAvailKb : memTotalKb;
            usedMb = usedKb / 1024;
            totalMb = memTotalKb / 1024;
            percent = Math.Clamp(usedMb * 100.0 / totalMb, 0, 100);
            return true;
        }
        catch
        {
            return false;
        }
    }

    private static CpuTick? ReadProcStat()
    {
        try
        {
            if (!File.Exists("/proc/stat")) return null;
            var line = File.ReadLines("/proc/stat").FirstOrDefault();
            if (line == null || !line.StartsWith("cpu ", StringComparison.Ordinal)) return null;
            var parts = line.Split(' ', StringSplitOptions.RemoveEmptyEntries);
            if (parts.Length < 5) return null;
            ulong total = 0;
            for (var i = 1; i < parts.Length; i++)
                total += ulong.Parse(parts[i], CultureInfo.InvariantCulture);
            var idle = ulong.Parse(parts[4], CultureInfo.InvariantCulture);
            if (parts.Length > 5)
                idle += ulong.Parse(parts[5], CultureInfo.InvariantCulture);
            return new CpuTick(idle, total, "proc");
        }
        catch
        {
            return null;
        }
    }

    private static long ParseKb(string line)
    {
        var parts = line.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        return parts.Length >= 2 && long.TryParse(parts[1], out var v) ? v : 0;
    }

    private static long? ReadLongFile(string path)
    {
        if (!File.Exists(path)) return null;
        var t = File.ReadAllText(path).Trim();
        return long.TryParse(t, NumberStyles.Integer, CultureInfo.InvariantCulture, out var v) ? v : null;
    }

    private static long? ReadCgroupMax(string path)
    {
        if (!File.Exists(path)) return null;
        var t = File.ReadAllText(path).Trim();
        if (t.Equals("max", StringComparison.OrdinalIgnoreCase)) return null;
        var first = t.Split(' ', StringSplitOptions.RemoveEmptyEntries)[0];
        return long.TryParse(first, NumberStyles.Integer, CultureInfo.InvariantCulture, out var v) ? v : null;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MemoryStatusEx
    {
        public uint Length;
        public uint MemoryLoad;
        public ulong TotalPhys;
        public ulong AvailPhys;
        public ulong TotalPageFile;
        public ulong AvailPageFile;
        public ulong TotalVirtual;
        public ulong AvailVirtual;
        public ulong AvailExtendedVirtual;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GlobalMemoryStatusEx(ref MemoryStatusEx lpBuffer);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetSystemTimes(out long idle, out long kernel, out long user);

    [System.Runtime.Versioning.SupportedOSPlatform("windows")]
    private static bool TryReadWindowsRam(out long usedMb, out long totalMb, out double percent)
    {
        usedMb = 0;
        totalMb = 0;
        percent = -1;
        try
        {
            var s = new MemoryStatusEx { Length = (uint)Marshal.SizeOf<MemoryStatusEx>() };
            if (!GlobalMemoryStatusEx(ref s) || s.TotalPhys == 0) return false;
            totalMb = (long)(s.TotalPhys / (1024 * 1024));
            usedMb = (long)((s.TotalPhys - s.AvailPhys) / (1024 * 1024));
            percent = Math.Clamp(s.MemoryLoad, 0, 100);
            return true;
        }
        catch
        {
            return false;
        }
    }

    [System.Runtime.Versioning.SupportedOSPlatform("windows")]
    private static bool TryReadWindowsCpu(out ulong idle, out ulong total)
    {
        idle = 0;
        total = 0;
        try
        {
            if (!GetSystemTimes(out var idleT, out var kernelT, out var userT)) return false;
            // Kernel time includes idle.
            var kernel = unchecked((ulong)kernelT);
            var user = unchecked((ulong)userT);
            idle = unchecked((ulong)idleT);
            total = kernel + user;
            return total > 0;
        }
        catch
        {
            return false;
        }
    }
}

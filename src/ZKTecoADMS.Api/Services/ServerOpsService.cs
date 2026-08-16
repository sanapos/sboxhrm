using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace ZKTecoADMS.Api.Services;

/// <summary>SuperAdmin: dọn rác volume app + quản lý APK/phần mềm trong wwwroot/downloads.</summary>
public sealed class ServerOpsService(IWebHostEnvironment env, ILogger<ServerOpsService> logger)
{
    public const long MaxUploadBytes = 280L * 1024 * 1024;
    private static readonly Regex SafeName = new(@"^[A-Za-z0-9][A-Za-z0-9._-]{0,120}$", RegexOptions.Compiled);
    private static readonly HashSet<string> AllowedExt = new(StringComparer.OrdinalIgnoreCase)
    {
        ".apk", ".exe", ".msi", ".json", ".zip", ".bin"
    };
    private static readonly HashSet<string> ProtectedNames = new(StringComparer.OrdinalIgnoreCase)
    {
        "sbox-pos.apk", "sbox-pos-release.json",
        "sbox-print-agent.exe", "sbox-print-agent-release.json",
        "sbox-hrm.apk", "sbox-hrm-release.json",
        "zk_gateway.bin", "sbox-zk-gateway-release.json",
        "software-catalog.json"
    };
    private static readonly string[] WwwrootJunk =
    [
        "canvaskit", "flutter.js", "flutter_bootstrap.js", "flutter_service_worker.js",
        "main.dart.js", "version.json"
    ];
    private static readonly string[] WwwrootJunkIfFlutter =
    [
        "index.html", "manifest.json", "assets"
    ];

    public string WebRoot => env.WebRootPath ?? Path.Combine(env.ContentRootPath, "wwwroot");
    public string DownloadsDir => Path.Combine(WebRoot, "downloads");
    public string GcDir => Path.Combine(env.ContentRootPath, "gc");

    public object StorageSnapshot()
    {
        ServerResourceReader.TryReadDisk(out var usedMb, out var totalMb, out var freeMb, out var pct, out var mount);
        var www = DirSize(WebRoot);
        var dl = DirSize(DownloadsDir);
        var junk = EstimateJunkBytes();
        object? hostGc = null;
        var statusPath = Path.Combine(GcDir, "status.json");
        if (File.Exists(statusPath))
        {
            try { hostGc = JsonSerializer.Deserialize<object>(File.ReadAllText(statusPath)); }
            catch { /* ignore */ }
        }

        return new
        {
            diskUsedMb = usedMb,
            diskTotalMb = totalMb,
            diskFreeMb = freeMb,
            diskPercent = pct,
            diskMount = mount,
            wwwrootMb = www / (1024 * 1024),
            downloadsMb = dl / (1024 * 1024),
            junkBytes = junk,
            hostGc,
            hostGcReady = Directory.Exists(GcDir),
            sampledAt = DateTime.UtcNow
        };
    }

    public object CleanupApp(bool apply)
    {
        var removed = new List<object>();
        long bytes = 0;
        var names = WwwrootJunk.ToList();
        if (ExistsSafe(Path.Combine(WebRoot, "flutter.js")) ||
            ExistsSafe(Path.Combine(WebRoot, "canvaskit")))
            names.AddRange(WwwrootJunkIfFlutter);

        foreach (var name in names)
        {
            var path = Path.Combine(WebRoot, name);
            if (!ExistsSafe(path)) continue;
            var size = SizeOf(path);
            if (apply)
            {
                try
                {
                    if (Directory.Exists(path)) Directory.Delete(path, true);
                    else File.Delete(path);
                    removed.Add(new { path = name, bytes = size, deleted = true });
                    bytes += size;
                }
                catch (Exception ex)
                {
                    logger.LogWarning(ex, "Không xóa được {Path}", path);
                    removed.Add(new { path = name, bytes = size, deleted = false, error = ex.Message });
                }
            }
            else
            {
                removed.Add(new { path = name, bytes = size, deleted = false });
                bytes += size;
            }
        }

        return new { apply, freedBytes = bytes, items = removed };
    }

    public bool RequestHostGc()
    {
        try
        {
            Directory.CreateDirectory(GcDir);
            File.WriteAllText(Path.Combine(GcDir, "request"), DateTime.UtcNow.ToString("o"));
            return true;
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Không ghi được yêu cầu dọn host");
            return false;
        }
    }

    public IReadOnlyList<object> ListReleases()
    {
        Directory.CreateDirectory(DownloadsDir);
        return Directory.EnumerateFileSystemEntries(DownloadsDir)
            .Select(p =>
            {
                var name = Path.GetFileName(p);
                var isDir = Directory.Exists(p);
                var fi = isDir ? null : new FileInfo(p);
                return (object)new
                {
                    name,
                    bytes = isDir ? DirSize(p) : fi!.Length,
                    updatedAt = (isDir ? Directory.GetLastWriteTimeUtc(p) : fi!.LastWriteTimeUtc),
                    kind = Classify(name),
                    protectedFile = ProtectedNames.Contains(name),
                    downloadUrl = isDir ? null : $"/api/system-admin/server/releases/{Uri.EscapeDataString(name)}/file"
                };
            })
            .ToList();
    }

    public async Task<(bool ok, string message, string? savedAs)> SaveUploadAsync(
        IFormFile file, string? kind, string? versionName, int versionCode, string? releaseNotes, bool activate)
    {
        if (file.Length <= 0) return (false, "File trống", null);
        if (file.Length > MaxUploadBytes) return (false, "File quá lớn (tối đa 280 MB)", null);

        var rawName = Path.GetFileName(file.FileName);
        if (!SafeName.IsMatch(rawName)) return (false, "Tên file không hợp lệ (chỉ chữ, số, . _ -)", null);
        var ext = Path.GetExtension(rawName);
        if (!AllowedExt.Contains(ext)) return (false, $"Không nhận loại {ext}", null);

        await using var probe = file.OpenReadStream();
        if (!LooksSafe(probe, ext)) return (false, "Nội dung file không khớp phần mở rộng", null);
        probe.Position = 0;

        Directory.CreateDirectory(DownloadsDir);
        var destName = activate ? CanonicalName(kind, ext) ?? rawName : rawName;
        if (!SafeName.IsMatch(destName)) return (false, "Tên đích không hợp lệ", null);
        var dest = Path.Combine(DownloadsDir, destName);

        var tmp = dest + ".uploading";
        await using (var fs = File.Create(tmp))
            await file.CopyToAsync(fs);
        File.Move(tmp, dest, overwrite: true);

        if (activate && !string.Equals(ext, ".json", StringComparison.OrdinalIgnoreCase))
            WriteReleaseJson(kind, destName, versionName, versionCode, releaseNotes, file.Length);

        logger.LogWarning("SuperAdmin uploaded {Name} ({Bytes} bytes) kind={Kind} activate={Activate}",
            destName, file.Length, kind, activate);
        return (true, "Đã lưu", destName);
    }

    public (bool ok, string message) DeleteRelease(string name, bool force)
    {
        if (!SafeName.IsMatch(name)) return (false, "Tên không hợp lệ");
        var path = Path.Combine(DownloadsDir, name);
        if (!ExistsSafe(path)) return (false, "Không thấy file");
        if (ProtectedNames.Contains(name) && !force)
            return (false, "File đang dùng cho OTA — xác nhận force để xóa");
        try
        {
            if (Directory.Exists(path)) Directory.Delete(path, true);
            else File.Delete(path);
            return (true, "Đã xóa");
        }
        catch (Exception ex)
        {
            return (false, ex.Message);
        }
    }

    public string? ResolveDownload(string name)
    {
        if (!SafeName.IsMatch(name)) return null;
        var path = Path.Combine(DownloadsDir, name);
        return File.Exists(path) ? path : null;
    }

    private void WriteReleaseJson(string? kind, string fileName, string? versionName, int versionCode, string? notes, long bytes)
    {
        var jsonName = kind?.ToLowerInvariant() switch
        {
            "pos" => "sbox-pos-release.json",
            "hrm" => "sbox-hrm-release.json",
            "agent" => "sbox-print-agent-release.json",
            _ => null
        };
        if (jsonName == null) return;
        var payload = new Dictionary<string, object?>
        {
            ["versionName"] = string.IsNullOrWhiteSpace(versionName) ? "0.0.0" : versionName.Trim(),
            ["versionCode"] = versionCode > 0 ? versionCode : 1,
            ["releaseNotes"] = notes ?? "",
            ["publishedAt"] = DateTime.UtcNow.ToString("o"),
            ["forceUpdate"] = false,
            ["fileBytes"] = bytes,
            ["apkPath"] = kind == "pos" ? "/api/app/pos-android-apk" : $"/downloads/{fileName}",
            ["downloadPath"] = kind == "agent" ? "/api/app/print-agent-windows" : $"/downloads/{fileName}",
            ["apkUrl"] = $"/downloads/{fileName}"
        };
        var json = JsonSerializer.Serialize(payload, new JsonSerializerOptions { WriteIndented = true });
        File.WriteAllText(Path.Combine(DownloadsDir, jsonName), json, new UTF8Encoding(false));
    }

    private static string? CanonicalName(string? kind, string ext) =>
        kind?.ToLowerInvariant() switch
        {
            "pos" when ext.Equals(".apk", StringComparison.OrdinalIgnoreCase) => "sbox-pos.apk",
            "hrm" when ext.Equals(".apk", StringComparison.OrdinalIgnoreCase) => "sbox-hrm.apk",
            "agent" when ext.Equals(".exe", StringComparison.OrdinalIgnoreCase) => "sbox-print-agent.exe",
            _ => null
        };

    private static string Classify(string name)
    {
        var n = name.ToLowerInvariant();
        if (n.Contains("pos") && n.EndsWith(".apk")) return "pos";
        if (n.Contains("hrm") && n.EndsWith(".apk")) return "hrm";
        if (n.Contains("print-agent") || n.EndsWith(".exe")) return "agent";
        if (n.Contains("gateway") || n.EndsWith(".bin")) return "gateway";
        if (n.EndsWith(".json")) return "meta";
        return "software";
    }

    private static bool LooksSafe(Stream s, string ext)
    {
        Span<byte> buf = stackalloc byte[8];
        var n = s.Read(buf);
        if (n < 2) return false;
        return ext.ToLowerInvariant() switch
        {
            ".apk" or ".zip" => buf[0] == (byte)'P' && buf[1] == (byte)'K',
            ".exe" or ".msi" => buf[0] == (byte)'M' && buf[1] == (byte)'Z',
            ".json" => buf[0] is (byte)'{' or (byte)'[',
            ".bin" => n >= 4,
            _ => false
        };
    }

    private bool ExistsSafe(string path)
    {
        var full = Path.GetFullPath(path);
        var root = Path.GetFullPath(WebRoot);
        return full.StartsWith(root, StringComparison.OrdinalIgnoreCase) && (File.Exists(full) || Directory.Exists(full));
    }

    private static long SizeOf(string path) =>
        Directory.Exists(path) ? DirSize(path) : new FileInfo(path).Length;

    private static long DirSize(string path)
    {
        if (!Directory.Exists(path)) return 0;
        try
        {
            return new DirectoryInfo(path).EnumerateFiles("*", SearchOption.AllDirectories)
                .Sum(f => f.Length);
        }
        catch { return 0; }
    }

    private long EstimateJunkBytes()
    {
        var names = WwwrootJunk.AsEnumerable();
        if (ExistsSafe(Path.Combine(WebRoot, "flutter.js")) ||
            ExistsSafe(Path.Combine(WebRoot, "canvaskit")))
            names = names.Concat(WwwrootJunkIfFlutter);
        return names.Select(n => Path.Combine(WebRoot, n)).Where(ExistsSafe).Sum(SizeOf);
    }
}

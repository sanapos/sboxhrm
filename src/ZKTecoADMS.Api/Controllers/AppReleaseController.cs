using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// Bản phát hành client: SBOX POS APK (Android) + Print Agent (Windows) + ESP32 ZK Gateway.
/// </summary>
[ApiController]
[Route("api/app")]
public class AppReleaseController : ControllerBase
{
    private readonly IWebHostEnvironment _env;
    private readonly ILogger<AppReleaseController> _log;

    public AppReleaseController(IWebHostEnvironment env, ILogger<AppReleaseController> log)
    {
        _env = env;
        _log = log;
    }

    public record PosAndroidReleaseDto(
        string AppId,
        string VersionName,
        int VersionCode,
        string ApkUrl,
        string? ReleaseNotes,
        bool ForceUpdate,
        long? ApkBytes,
        DateTime? PublishedAt);

    public record PrintAgentReleaseDto(
        string AppId,
        string VersionName,
        int VersionCode,
        string DownloadUrl,
        string? ReleaseNotes,
        bool ForceUpdate,
        long? FileBytes,
        DateTime? PublishedAt,
        string Platform);

    public record ZkGatewayReleaseDto(
        string AppId,
        string VersionName,
        int VersionCode,
        string? AppSha,
        string DownloadUrl,
        string? ReleaseNotes,
        long? FileBytes,
        DateTime? PublishedAt);

    [AllowAnonymous]
    [HttpGet("pos-android-release")]
    public ActionResult<AppResponse<PosAndroidReleaseDto>> GetPosAndroidRelease()
    {
        var webRoot = _env.WebRootPath ?? Path.Combine(_env.ContentRootPath, "wwwroot");
        var jsonPath = Path.Combine(webRoot, "downloads", "sbox-pos-release.json");
        var apkPath = Path.Combine(webRoot, "downloads", "sbox-pos.apk");

        if (!System.IO.File.Exists(jsonPath))
        {
            return Ok(AppResponse<PosAndroidReleaseDto>.Fail(
                "Chưa cấu hình bản phát hành POS (downloads/sbox-pos-release.json)."));
        }

        try
        {
            using var doc = JsonDocument.Parse(System.IO.File.ReadAllText(jsonPath));
            var root = doc.RootElement;
            var versionName = root.TryGetProperty("versionName", out var vn) ? vn.GetString() ?? "0" : "0";
            var versionCode = root.TryGetProperty("versionCode", out var vc) ? vc.GetInt32() : 0;
            var notes = root.TryGetProperty("releaseNotes", out var rn) ? rn.GetString() : null;
            var force = root.TryGetProperty("forceUpdate", out var fu) && fu.GetBoolean();
            var relativeApk = root.TryGetProperty("apkPath", out var ap)
                ? ap.GetString() ?? "/api/app/pos-android-apk"
                : "/api/app/pos-android-apk";

            if (!relativeApk.StartsWith('/')) relativeApk = "/" + relativeApk;

            long? bytes = null;
            DateTime? published = null;
            if (System.IO.File.Exists(apkPath))
            {
                var fi = new FileInfo(apkPath);
                bytes = fi.Length;
                published = fi.LastWriteTimeUtc;
            }

            var apkUrl = BuildPublicUrl(relativeApk);

            return Ok(AppResponse<PosAndroidReleaseDto>.Success(new PosAndroidReleaseDto(
                AppId: "sbox.sana.vn.pos.flutter",
                VersionName: versionName,
                VersionCode: versionCode,
                ApkUrl: apkUrl,
                ReleaseNotes: notes,
                ForceUpdate: force,
                ApkBytes: bytes,
                PublishedAt: published)));
        }
        catch (Exception ex)
        {
            _log.LogWarning(ex, "Đọc sbox-pos-release.json thất bại");
            return Ok(AppResponse<PosAndroidReleaseDto>.Fail("Không đọc được thông tin bản phát hành."));
        }
    }

    /// <summary>Tải APK trực tiếp (phòng khi static file / nginx chưa trỏ /downloads).</summary>
    [AllowAnonymous]
    [HttpGet("pos-android-apk")]
    public IActionResult DownloadPosAndroidApk()
    {
        var webRoot = _env.WebRootPath ?? Path.Combine(_env.ContentRootPath, "wwwroot");
        var apkPath = Path.Combine(webRoot, "downloads", "sbox-pos.apk");
        if (!System.IO.File.Exists(apkPath))
            return NotFound("Chưa có file sbox-pos.apk trên server.");

        return PhysicalFile(
            apkPath,
            "application/vnd.android.package-archive",
            fileDownloadName: "sbox-pos.apk",
            enableRangeProcessing: true);
    }

    [AllowAnonymous]
    [HttpGet("print-agent-release")]
    public ActionResult<AppResponse<PrintAgentReleaseDto>> GetPrintAgentRelease()
    {
        var webRoot = _env.WebRootPath ?? Path.Combine(_env.ContentRootPath, "wwwroot");
        var jsonPath = Path.Combine(webRoot, "downloads", "sbox-print-agent-release.json");
        var exePath = Path.Combine(webRoot, "downloads", "sbox-print-agent.exe");

        if (!System.IO.File.Exists(jsonPath))
        {
            return Ok(AppResponse<PrintAgentReleaseDto>.Fail(
                "Chưa cấu hình bản phát hành Print Agent (downloads/sbox-print-agent-release.json)."));
        }

        try
        {
            using var doc = JsonDocument.Parse(System.IO.File.ReadAllText(jsonPath));
            var root = doc.RootElement;
            var versionName = root.TryGetProperty("versionName", out var vn) ? vn.GetString() ?? "0" : "0";
            var versionCode = root.TryGetProperty("versionCode", out var vc) ? vc.GetInt32() : 0;
            var notes = root.TryGetProperty("releaseNotes", out var rn) ? rn.GetString() : null;
            var force = root.TryGetProperty("forceUpdate", out var fu) && fu.GetBoolean();
            var relative = root.TryGetProperty("downloadPath", out var dp)
                ? dp.GetString() ?? "/api/app/print-agent-windows"
                : "/api/app/print-agent-windows";
            if (!relative.StartsWith('/')) relative = "/" + relative;

            long? bytes = null;
            DateTime? published = null;
            if (root.TryGetProperty("publishedAt", out var pa) &&
                DateTime.TryParse(pa.GetString(), null,
                    System.Globalization.DateTimeStyles.RoundtripKind, out var publishedParsed))
            {
                published = publishedParsed.ToUniversalTime();
            }
            if (System.IO.File.Exists(exePath))
            {
                var fi = new FileInfo(exePath);
                bytes = fi.Length;
                published ??= fi.LastWriteTimeUtc;
            }

            return Ok(AppResponse<PrintAgentReleaseDto>.Success(new PrintAgentReleaseDto(
                AppId: "sbox.print.agent.win",
                VersionName: versionName,
                VersionCode: versionCode,
                DownloadUrl: BuildPublicUrl(relative),
                ReleaseNotes: notes,
                ForceUpdate: force,
                FileBytes: bytes,
                PublishedAt: published,
                Platform: "windows")));
        }
        catch (Exception ex)
        {
            _log.LogWarning(ex, "Đọc sbox-print-agent-release.json thất bại");
            return Ok(AppResponse<PrintAgentReleaseDto>.Fail("Không đọc được thông tin Print Agent."));
        }
    }

    /// <summary>Tải SBOX Print Agent (Windows) — hỗ trợ in từ web POS.</summary>
    [AllowAnonymous]
    [HttpGet("print-agent-windows")]
    public IActionResult DownloadPrintAgentWindows()
    {
        var webRoot = _env.WebRootPath ?? Path.Combine(_env.ContentRootPath, "wwwroot");
        var exePath = Path.Combine(webRoot, "downloads", "sbox-print-agent.exe");
        if (!System.IO.File.Exists(exePath))
            return NotFound("Chưa có file sbox-print-agent.exe trên server.");

        return PhysicalFile(
            exePath,
            "application/vnd.microsoft.portable-executable",
            fileDownloadName: "SboxPrintAgent.exe",
            enableRangeProcessing: true);
    }

    // ------------------------------------------------------------------
    // ESP32 ZK Gateway firmware (OTA)
    // ------------------------------------------------------------------

    /// <summary>Thông tin bản gateway mới nhất — Admin tải về để OTA LAN.</summary>
    [Authorize(Policy = PolicyNames.AtLeastAdmin)]
    [HttpGet("zk-gateway-release")]
    public ActionResult<AppResponse<ZkGatewayReleaseDto>> GetZkGatewayRelease()
    {
        var (_, jsonPath, binPath) = GatewayPaths();
        if (!System.IO.File.Exists(jsonPath))
        {
            return Ok(AppResponse<ZkGatewayReleaseDto>.Fail(
                "Chưa có bản firmware gateway trên server. SuperAdmin hãy upload zk_gateway.bin."));
        }

        try
        {
            using var doc = JsonDocument.Parse(System.IO.File.ReadAllText(jsonPath));
            var root = doc.RootElement;
            var versionName = root.TryGetProperty("versionName", out var vn) ? vn.GetString() ?? "0" : "0";
            var versionCode = root.TryGetProperty("versionCode", out var vc) ? vc.GetInt32() : 0;
            var appSha = root.TryGetProperty("appSha", out var sha) ? sha.GetString() : null;
            var notes = root.TryGetProperty("releaseNotes", out var rn) ? rn.GetString() : null;

            long? bytes = null;
            DateTime? published = null;
            if (root.TryGetProperty("publishedAt", out var pa) &&
                DateTime.TryParse(pa.GetString(), null,
                    System.Globalization.DateTimeStyles.RoundtripKind, out var publishedParsed))
            {
                published = publishedParsed.ToUniversalTime();
            }
            if (System.IO.File.Exists(binPath))
            {
                var fi = new FileInfo(binPath);
                bytes = fi.Length;
                published ??= fi.LastWriteTimeUtc;
            }
            else
            {
                return Ok(AppResponse<ZkGatewayReleaseDto>.Fail("Thiếu file zk_gateway.bin trên server."));
            }

            return Ok(AppResponse<ZkGatewayReleaseDto>.Success(new ZkGatewayReleaseDto(
                AppId: "sbox.zk.gateway.esp32c3",
                VersionName: versionName,
                VersionCode: versionCode,
                AppSha: appSha,
                DownloadUrl: BuildPublicUrl("/api/app/zk-gateway-bin"),
                ReleaseNotes: notes,
                FileBytes: bytes,
                PublishedAt: published)));
        }
        catch (Exception ex)
        {
            _log.LogWarning(ex, "Đọc sbox-zk-gateway-release.json thất bại");
            return Ok(AppResponse<ZkGatewayReleaseDto>.Fail("Không đọc được thông tin firmware gateway."));
        }
    }

    [Authorize(Policy = PolicyNames.AtLeastAdmin)]
    [HttpGet("zk-gateway-bin")]
    public IActionResult DownloadZkGatewayBin()
    {
        var (_, _, binPath) = GatewayPaths();
        if (!System.IO.File.Exists(binPath))
            return NotFound("Chưa có file zk_gateway.bin trên server.");

        return PhysicalFile(
            binPath,
            "application/octet-stream",
            fileDownloadName: "zk_gateway.bin",
            enableRangeProcessing: true);
    }

    /// <summary>SuperAdmin upload bản firmware mới (multipart: file + versionName + versionCode + releaseNotes + appSha).</summary>
    [Authorize(Roles = nameof(Roles.SuperAdmin))]
    [HttpPost("zk-gateway-upload")]
    [RequestSizeLimit(4_000_000)]
    [RequestFormLimits(MultipartBodyLengthLimit = 4_000_000)]
    public async Task<ActionResult<AppResponse<ZkGatewayReleaseDto>>> UploadZkGateway(
        IFormFile? file,
        [FromForm] string? versionName,
        [FromForm] int versionCode = 0,
        [FromForm] string? releaseNotes = null,
        [FromForm] string? appSha = null)
    {
        if (file == null || file.Length < 100_000)
            return Ok(AppResponse<ZkGatewayReleaseDto>.Fail("File firmware không hợp lệ (thiếu hoặc quá nhỏ)."));

        var ext = Path.GetExtension(file.FileName);
        if (!string.Equals(ext, ".bin", StringComparison.OrdinalIgnoreCase))
            return Ok(AppResponse<ZkGatewayReleaseDto>.Fail("Chỉ nhận tệp .bin (zk_gateway.bin)."));

        if (string.IsNullOrWhiteSpace(versionName))
            versionName = "0.0.0";
        if (versionCode <= 0)
            versionCode = (int)(DateTime.UtcNow.Subtract(new DateTime(2024, 1, 1)).TotalDays);

        var (_, jsonPath, binPath) = GatewayPaths();
        Directory.CreateDirectory(Path.GetDirectoryName(binPath)!);

        await using (var fs = System.IO.File.Create(binPath))
        {
            await file.CopyToAsync(fs);
        }

        // Nếu không gửi appSha — tính SHA-256 16 hex đầu của file (tham chiếu; khác appSha IDF nếu không truyền).
        if (string.IsNullOrWhiteSpace(appSha))
        {
            await using var read = System.IO.File.OpenRead(binPath);
            var hash = await SHA256.HashDataAsync(read);
            appSha = Convert.ToHexString(hash.AsSpan(0, 8)).ToLowerInvariant();
        }

        var meta = new
        {
            versionName,
            versionCode,
            appSha,
            releaseNotes,
            publishedAt = DateTime.UtcNow.ToString("o"),
            downloadPath = "/api/app/zk-gateway-bin"
        };
        await System.IO.File.WriteAllTextAsync(
            jsonPath,
            JsonSerializer.Serialize(meta, new JsonSerializerOptions { WriteIndented = true }),
            Encoding.UTF8);

        _log.LogWarning(
            "SuperAdmin uploaded ZK gateway firmware: {Version} code={Code} sha={Sha} bytes={Bytes}",
            versionName, versionCode, appSha, file.Length);

        return Ok(AppResponse<ZkGatewayReleaseDto>.Success(new ZkGatewayReleaseDto(
            AppId: "sbox.zk.gateway.esp32c3",
            VersionName: versionName,
            VersionCode: versionCode,
            AppSha: appSha,
            DownloadUrl: BuildPublicUrl("/api/app/zk-gateway-bin"),
            ReleaseNotes: releaseNotes,
            FileBytes: file.Length,
            PublishedAt: DateTime.UtcNow)));
    }

    private (string WebRoot, string JsonPath, string BinPath) GatewayPaths()
    {
        var webRoot = _env.WebRootPath ?? Path.Combine(_env.ContentRootPath, "wwwroot");
        var dir = Path.Combine(webRoot, "downloads");
        return (
            webRoot,
            Path.Combine(dir, "sbox-zk-gateway-release.json"),
            Path.Combine(dir, "zk_gateway.bin"));
    }

    private string BuildPublicUrl(string relativePath)
    {
        var forwardedProto = Request.Headers["X-Forwarded-Proto"].FirstOrDefault();
        var scheme = string.IsNullOrWhiteSpace(forwardedProto) ? Request.Scheme : forwardedProto!;
        if (!string.Equals(scheme, "https", StringComparison.OrdinalIgnoreCase)
            && string.Equals(Request.Host.Host, "sboxhrm.com", StringComparison.OrdinalIgnoreCase))
        {
            scheme = "https";
        }
        return $"{scheme}://{Request.Host}".TrimEnd('/') + relativePath;
    }
}

using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Controllers;

[Authorize(Roles = nameof(Roles.SuperAdmin))]
[Route("api/system-admin/server")]
public class ServerOpsController(ServerOpsService ops, ILogger<ServerOpsController> logger)
    : AuthenticatedControllerBase
{
    public class CleanupDto
    {
        public string? Scope { get; set; }
        public bool Apply { get; set; }
    }

    [HttpGet("storage")]
    public ActionResult<AppResponse<object>> Storage() =>
        Ok(AppResponse<object>.Success(ops.StorageSnapshot()));

    [HttpPost("cleanup")]
    public ActionResult<AppResponse<object>> Cleanup([FromBody] CleanupDto? dto)
    {
        var scope = (dto?.Scope ?? "app").Trim().ToLowerInvariant();
        var apply = dto?.Apply == true;
        object? host = null;
        if (scope is "host" or "all")
        {
            if (apply)
            {
                var ok = ops.RequestHostGc();
                host = new
                {
                    requested = ok,
                    message = ok
                        ? "Đã gửi yêu cầu dọn host. Cron chạy trong vòng 1 phút."
                        : "Không ghi được yêu cầu (thiếu mount /opt/zkteco/gc)."
                };
            }
            else
            {
                host = new
                {
                    requested = false,
                    message = "Dọn host: image Docker không chạy, cache build, journal, rác /root /opt /tmp. Không đụng volume DB/upload."
                };
            }
        }

        var app = scope is "app" or "all" ? ops.CleanupApp(apply) : null;
        logger.LogWarning("SuperAdmin cleanup scope={Scope} apply={Apply}", scope, apply);
        return Ok(AppResponse<object>.Success(new { scope, apply, app, host, storage = ops.StorageSnapshot() }));
    }

    [HttpGet("releases")]
    public ActionResult<AppResponse<object>> Releases() =>
        Ok(AppResponse<object>.Success(new { files = ops.ListReleases() }));

    [HttpPost("releases/upload")]
    [RequestSizeLimit(ServerOpsService.MaxUploadBytes)]
    [RequestFormLimits(MultipartBodyLengthLimit = ServerOpsService.MaxUploadBytes)]
    public async Task<ActionResult<AppResponse<object>>> Upload(
        IFormFile? file,
        [FromForm] string? kind,
        [FromForm] string? versionName,
        [FromForm] int versionCode = 0,
        [FromForm] string? releaseNotes = null,
        [FromForm] bool activate = false)
    {
        if (file == null) return Ok(AppResponse<object>.Fail("Chưa chọn file"));
        var (ok, message, savedAs) = await ops.SaveUploadAsync(
            file, kind, versionName, versionCode, releaseNotes, activate);
        return Ok(ok
            ? AppResponse<object>.Success(new { savedAs, message, files = ops.ListReleases() })
            : AppResponse<object>.Fail(message));
    }

    [HttpDelete("releases/{name}")]
    public ActionResult<AppResponse<object>> Delete(string name, [FromQuery] bool force = false)
    {
        var (ok, message) = ops.DeleteRelease(name, force);
        return Ok(ok
            ? AppResponse<object>.Success(new { message, files = ops.ListReleases() })
            : AppResponse<object>.Fail(message));
    }

    [HttpGet("releases/{name}/file")]
    public IActionResult Download(string name)
    {
        var path = ops.ResolveDownload(name);
        if (path == null) return NotFound();
        var ext = Path.GetExtension(path).ToLowerInvariant();
        var ctype = ext switch
        {
            ".apk" => "application/vnd.android.package-archive",
            ".exe" => "application/vnd.microsoft.portable-executable",
            ".json" => "application/json",
            ".zip" => "application/zip",
            _ => "application/octet-stream"
        };
        return PhysicalFile(path, ctype, Path.GetFileName(path), enableRangeProcessing: true);
    }
}

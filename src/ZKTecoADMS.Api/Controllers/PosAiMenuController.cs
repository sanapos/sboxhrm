using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>Chụp ảnh menu → AI đọc món → xem trước → tạo nhóm hàng / hàng hóa / size.</summary>
[ApiController]
[Authorize]
[Route("api/pos/ai/menu")]
public class PosAiMenuController(
    PosAiMenuService menuService,
    ILogger<PosAiMenuController> logger) : AuthenticatedControllerBase
{
    static readonly HashSet<string> ImageTypes = new(StringComparer.OrdinalIgnoreCase)
    {
        "image/jpeg", "image/png", "image/webp", "image/heic", "image/heif",
    };

    [HttpPost("scan")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Create)]
    [RequestSizeLimit(PosAiMenuService.MaxTotalBytes + 1_000_000)]
    public async Task<ActionResult<AppResponse<MenuScanResultDto>>> Scan(
        [FromForm] List<IFormFile> files, CancellationToken ct)
    {
        if (files == null || files.Count == 0)
            return BadRequest(AppResponse<MenuScanResultDto>.Fail("Chọn ít nhất một ảnh menu."));
        if (files.Count > PosAiMenuService.MaxImages)
            return BadRequest(AppResponse<MenuScanResultDto>.Fail($"Tối đa {PosAiMenuService.MaxImages} ảnh mỗi lần."));
        if (files.Sum(f => f.Length) > PosAiMenuService.MaxTotalBytes)
            return BadRequest(AppResponse<MenuScanResultDto>.Fail("Ảnh quá lớn (tối đa 15 MB mỗi lần) — chụp lại hoặc chia nhỏ."));

        var images = new List<AiFilePart>();
        foreach (var f in files)
        {
            await using var ms = new MemoryStream();
            await f.CopyToAsync(ms, ct);
            var bytes = ms.ToArray();
            // Nhận dạng theo nội dung file trước (tên / Content-Type từ trình duyệt có thể thiếu hoặc sai).
            var mime = SniffImageMime(bytes)
                ?? (string.IsNullOrWhiteSpace(f.ContentType) || f.ContentType == "application/octet-stream"
                    ? GuessMime(f.FileName)
                    : f.ContentType);
            if (!ImageTypes.Contains(mime))
                return BadRequest(AppResponse<MenuScanResultDto>.Fail($"«{f.FileName}» không phải ảnh (JPG/PNG/WEBP/HEIC)."));
            images.Add(new AiFilePart(mime, bytes));
        }

        try
        {
            var result = await menuService.ScanAsync(RequiredStoreId, images, ct);
            if (result.Items.Count == 0)
                return Ok(AppResponse<MenuScanResultDto>.Fail("Không đọc được món nào — chụp rõ, thẳng và đủ sáng rồi thử lại."));
            return Ok(AppResponse<MenuScanResultDto>.Success(result));
        }
        catch (AiApiException ex)
        {
            logger.LogWarning("AI menu scan failed ({Status}): {Message}", ex.StatusCode, ex.Message);
            return Ok(AppResponse<MenuScanResultDto>.Fail(ex.Message));
        }
        catch (InvalidOperationException ex)
        {
            return Ok(AppResponse<MenuScanResultDto>.Fail(ex.Message));
        }
        catch (System.Text.Json.JsonException ex)
        {
            logger.LogWarning(ex, "AI menu scan returned invalid JSON");
            return Ok(AppResponse<MenuScanResultDto>.Fail("AI trả kết quả không đọc được — vui lòng thử lại."));
        }
    }

    public sealed record MenuImportRequest(List<MenuItemDto> Items);

    [HttpPost("import")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<MenuImportResultDto>>> Import(
        [FromBody] MenuImportRequest request, CancellationToken ct)
    {
        if (request.Items == null || request.Items.Count == 0)
            return BadRequest(AppResponse<MenuImportResultDto>.Fail("Chưa chọn món nào."));
        if (request.Items.Count > 500)
            return BadRequest(AppResponse<MenuImportResultDto>.Fail("Tối đa 500 món mỗi lần."));
        var result = await menuService.ImportAsync(RequiredStoreId, request.Items, CurrentUserEmail, ct);
        return Ok(AppResponse<MenuImportResultDto>.Success(result));
    }

    static string? SniffImageMime(byte[] b)
    {
        if (b.Length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) return "image/jpeg";
        if (b.Length >= 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) return "image/png";
        if (b.Length >= 12 && b[0] == (byte)'R' && b[1] == (byte)'I' && b[2] == (byte)'F' && b[3] == (byte)'F'
            && b[8] == (byte)'W' && b[9] == (byte)'E' && b[10] == (byte)'B' && b[11] == (byte)'P') return "image/webp";
        if (b.Length >= 12 && b[4] == (byte)'f' && b[5] == (byte)'t' && b[6] == (byte)'y' && b[7] == (byte)'p')
        {
            var brand = System.Text.Encoding.ASCII.GetString(b, 8, 4);
            if (brand is "heic" or "heix" or "hevc" or "mif1" or "msf1") return "image/heic";
        }
        return null;
    }

    static string GuessMime(string? fileName) => Path.GetExtension(fileName ?? "").ToLowerInvariant() switch
    {
        ".png" => "image/png",
        ".webp" => "image/webp",
        ".heic" => "image/heic",
        ".heif" => "image/heif",
        _ => "image/jpeg",
    };
}

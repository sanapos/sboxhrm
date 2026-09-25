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
            var mime = string.IsNullOrWhiteSpace(f.ContentType) || f.ContentType == "application/octet-stream"
                ? GuessMime(f.FileName)
                : f.ContentType;
            if (!ImageTypes.Contains(mime))
                return BadRequest(AppResponse<MenuScanResultDto>.Fail($"«{f.FileName}» không phải ảnh (JPG/PNG/WEBP/HEIC)."));
            await using var ms = new MemoryStream();
            await f.CopyToAsync(ms, ct);
            images.Add(new AiFilePart(mime, ms.ToArray()));
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

    static string GuessMime(string? fileName) => Path.GetExtension(fileName ?? "").ToLowerInvariant() switch
    {
        ".png" => "image/png",
        ".webp" => "image/webp",
        ".heic" => "image/heic",
        ".heif" => "image/heif",
        _ => "image/jpeg",
    };
}

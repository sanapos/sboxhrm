using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>Chụp ảnh menu / file Excel → AI đọc món → xem trước → tạo nhóm hàng / hàng hóa / size.</summary>
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
        if (files.FirstOrDefault(f => f.Length > PosAiMenuService.MaxImageBytes) is { } big)
            return BadRequest(AppResponse<MenuScanResultDto>.Fail(
                $"Ảnh «{big.FileName}» quá lớn (tối đa {PosAiMenuService.MaxImageBytes / 1024 / 1024} MB mỗi ảnh) — chụp lại hoặc giảm độ phân giải."));
        if (files.Sum(f => f.Length) > PosAiMenuService.MaxTotalBytes)
            return BadRequest(AppResponse<MenuScanResultDto>.Fail(
                $"Tổng dung lượng ảnh quá lớn (tối đa {PosAiMenuService.MaxTotalBytes / 1024 / 1024} MB mỗi lần) — bớt ảnh rồi đọc tiếp."));

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

        return await RunScanAsync(() => menuService.ScanAsync(RequiredStoreId, images, ct),
            "Không đọc được món nào — chụp rõ, thẳng và đủ sáng rồi thử lại.", ct);
    }

    /// <summary>
    /// File Excel (.xlsx) / CSV lộn xộn → AI đọc ra danh sách món (cùng dạng kết quả với ảnh menu) → xem trước → tạo hàng.
    /// File có cột rõ ràng / nhiều dòng nên dùng «Nhập Excel» thường.
    /// </summary>
    [HttpPost("scan-sheet")]
    [RequireModulePermission("PosProducts", ModulePermissionAction.Create)]
    [RequestSizeLimit(PosMenuSheetReader.MaxFileBytes + 1_000_000)]
    public async Task<ActionResult<AppResponse<MenuScanResultDto>>> ScanSheet(IFormFile? file, CancellationToken ct)
    {
        if (file == null || file.Length == 0)
            return BadRequest(AppResponse<MenuScanResultDto>.Fail("Chọn file Excel (.xlsx) hoặc CSV."));
        if (file.Length > PosMenuSheetReader.MaxFileBytes)
            return BadRequest(AppResponse<MenuScanResultDto>.Fail(
                $"File quá lớn (tối đa {PosMenuSheetReader.MaxFileBytes / 1024 / 1024} MB) — dùng «Nhập Excel» thường hoặc chia nhỏ file."));
        var ext = Path.GetExtension(file.FileName ?? "").ToLowerInvariant();
        if (ext == ".xls")
            return BadRequest(AppResponse<MenuScanResultDto>.Fail(PosMenuSheetReader.XlsMessage));
        if (ext.Length > 0 && !PosMenuSheetReader.SupportedExtensions.Contains(ext))
            return BadRequest(AppResponse<MenuScanResultDto>.Fail("Chỉ nhận file Excel .xlsx hoặc .csv."));

        MenuSheetText sheet;
        try
        {
            await using var ms = new MemoryStream();
            await file.CopyToAsync(ms, ct);
            sheet = PosMenuSheetReader.Read(ms.ToArray(), file.FileName);
        }
        catch (InvalidOperationException ex)
        {
            return Ok(AppResponse<MenuScanResultDto>.Fail(ex.Message));
        }

        return await RunScanAsync(() => menuService.ScanSheetAsync(RequiredStoreId, sheet, ct),
            "Không đọc được món nào trong file — kiểm tra file có cột tên món và giá.", ct);
    }

    async Task<ActionResult<AppResponse<MenuScanResultDto>>> RunScanAsync(
        Func<Task<MenuScanResultDto>> scan, string emptyMessage, CancellationToken ct)
    {
        try
        {
            var result = await scan();
            if (result.Items.Count == 0)
            {
                var why = result.Warnings is { Count: > 0 } w ? " (" + string.Join("; ", w) + ")" : "";
                return Ok(AppResponse<MenuScanResultDto>.Fail(emptyMessage + why));
            }
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
        catch (OperationCanceledException) when (!ct.IsCancellationRequested)
        {
            // Hết thời gian chờ AI (giới hạn tổng ~150 s) hoặc HttpClient timeout — không phải người dùng hủy.
            logger.LogWarning("AI menu scan timed out");
            return Ok(AppResponse<MenuScanResultDto>.Fail(
                "AI đọc quá lâu (quá 150 giây) — bớt số ảnh / chia nhỏ file rồi thử lại, hoặc thử lại sau ít phút."));
        }
        catch (HttpRequestException ex)
        {
            logger.LogWarning(ex, "AI menu scan network error");
            return Ok(AppResponse<MenuScanResultDto>.Fail(
                "Không kết nối được máy chủ AI (Google) — kiểm tra mạng của máy chủ rồi thử lại sau."));
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
        try
        {
            var result = await menuService.ImportAsync(RequiredStoreId, request.Items, CurrentUserEmail, ct);
            return Ok(AppResponse<MenuImportResultDto>.Success(result));
        }
        catch (DbUpdateException ex)
        {
            // Bấm «Tạo» hai lần / hai máy cùng lúc → trùng mã hàng (unique StoreId + ProductCode).
            logger.LogWarning(ex, "AI menu import save failed");
            return Ok(AppResponse<MenuImportResultDto>.Fail(
                "Không lưu được vì trùng mã hàng — có thể đang tạo cùng lúc (bấm hai lần). Tải lại danh sách hàng hóa rồi thử lại; món đã tạo sẽ được bỏ qua."));
        }
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

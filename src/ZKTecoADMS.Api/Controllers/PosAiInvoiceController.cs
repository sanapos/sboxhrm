using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Api.Middlewares;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>Chụp hóa đơn nhà cung cấp → AI đọc → xem trước / sửa → tạo phiếu nhập (tạm hoặc hoàn thành).</summary>
[ApiController]
[Authorize]
[Route("api/pos/ai/purchase-invoice")]
public class PosAiInvoiceController(
    PosAiInvoiceService invoiceService,
    ILogger<PosAiInvoiceController> logger) : AuthenticatedControllerBase
{
    // Cùng quyền với «Tạo phiếu nhập» (POST api/pos/purchase/receipts dùng PosPurchaseReceipts + Edit).
    const string Module = "PosPurchaseReceipts";

    [HttpPost("scan")]
    [RequireModulePermission(Module, ModulePermissionAction.Edit)]
    [RequestSizeLimit(PosAiMenuService.MaxTotalBytes + 1_000_000)]
    public async Task<ActionResult<AppResponse<InvoiceScanResultDto>>> Scan(
        [FromForm] List<IFormFile> files, CancellationToken ct)
    {
        if (files == null || files.Count == 0)
            return BadRequest(AppResponse<InvoiceScanResultDto>.Fail("Chụp hoặc chọn ít nhất một ảnh hóa đơn."));
        if (files.Count > PosAiInvoiceService.MaxImages)
            return BadRequest(AppResponse<InvoiceScanResultDto>.Fail($"Tối đa {PosAiInvoiceService.MaxImages} ảnh mỗi hóa đơn."));
        if (files.FirstOrDefault(f => f.Length > PosAiMenuService.MaxImageBytes) is { } big)
            return BadRequest(AppResponse<InvoiceScanResultDto>.Fail(
                $"Ảnh «{big.FileName}» quá lớn (tối đa {PosAiMenuService.MaxImageBytes / 1024 / 1024} MB mỗi ảnh) — chụp lại hoặc giảm độ phân giải."));
        if (files.Sum(f => f.Length) > PosAiMenuService.MaxTotalBytes)
            return BadRequest(AppResponse<InvoiceScanResultDto>.Fail(
                $"Tổng dung lượng ảnh quá lớn (tối đa {PosAiMenuService.MaxTotalBytes / 1024 / 1024} MB mỗi lần) — bớt ảnh rồi thử lại."));

        var images = new List<AiFilePart>();
        foreach (var f in files)
        {
            await using var ms = new MemoryStream();
            await f.CopyToAsync(ms, ct);
            var bytes = ms.ToArray();
            var mime = PosAiImageUpload.ResolveMime(bytes, f.ContentType, f.FileName);
            if (mime == null)
                return BadRequest(AppResponse<InvoiceScanResultDto>.Fail($"«{f.FileName}» không phải ảnh (JPG/PNG/WEBP/HEIC)."));
            images.Add(new AiFilePart(mime, bytes));
        }

        try
        {
            var result = await invoiceService.ScanAsync(RequiredStoreId, images, ct);
            if (result.Lines.Count == 0)
            {
                var why = result.Warnings is { Count: > 0 } w ? " (" + string.Join("; ", w) + ")" : "";
                return Ok(AppResponse<InvoiceScanResultDto>.Fail(
                    "Không đọc được dòng hàng nào — chụp thẳng, rõ, đủ sáng và lấy hết bảng hàng rồi thử lại." + why));
            }
            return Ok(AppResponse<InvoiceScanResultDto>.Success(result));
        }
        catch (AiApiException ex)
        {
            logger.LogWarning("AI invoice scan failed ({Status}): {Message}", ex.StatusCode, ex.Message);
            return Ok(AppResponse<InvoiceScanResultDto>.Fail(ex.Message));
        }
        catch (InvalidOperationException ex)
        {
            return Ok(AppResponse<InvoiceScanResultDto>.Fail(ex.Message));
        }
        catch (System.Text.Json.JsonException ex)
        {
            logger.LogWarning(ex, "AI invoice scan returned invalid JSON");
            return Ok(AppResponse<InvoiceScanResultDto>.Fail("AI trả kết quả không đọc được — vui lòng thử lại."));
        }
        catch (OperationCanceledException) when (!ct.IsCancellationRequested)
        {
            // Hết thời gian chờ AI (~150 s) hoặc HttpClient timeout — không phải người dùng hủy.
            logger.LogWarning("AI invoice scan timed out");
            return Ok(AppResponse<InvoiceScanResultDto>.Fail(
                "AI đọc quá lâu (quá 150 giây) — bớt số ảnh rồi thử lại, hoặc thử lại sau ít phút."));
        }
        catch (HttpRequestException ex)
        {
            logger.LogWarning(ex, "AI invoice scan network error");
            return Ok(AppResponse<InvoiceScanResultDto>.Fail(
                "Không kết nối được máy chủ AI (Google) — kiểm tra mạng của máy chủ rồi thử lại sau."));
        }
    }

    [HttpPost("confirm")]
    [RequireModulePermission(Module, ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<InvoiceConfirmResultDto>>> Confirm(
        [FromBody] InvoiceConfirmRequest request, CancellationToken ct)
    {
        if (request?.Lines == null || request.Lines.Count == 0)
            return BadRequest(AppResponse<InvoiceConfirmResultDto>.Fail("Chưa có dòng hàng nào."));

        // Tạo NCC / hàng mới cần quyền thêm hàng hóa (như màn Nhà cung cấp / Hàng hóa).
        var createsMaster = request.Lines.Any(l => l.ProductId == null && l.CreateProduct)
                            || (request.SupplierId == null && request.CreateSupplier);
        if (createsMaster && !IsAdmin)
        {
            var perms = HttpContext.RequestServices.GetRequiredService<IModulePermissionService>();
            if (!await perms.HasPermissionAsync(CurrentUserId, CurrentUserRole, CurrentStoreId,
                    "PosProducts", ModulePermissionAction.Create))
                return StatusCode(403, AppResponse<InvoiceConfirmResultDto>.Fail(
                    "Bạn chưa có quyền thêm hàng hóa / nhà cung cấp — chọn hàng, NCC có sẵn hoặc nhờ quản lý cấp quyền."));
        }

        try
        {
            var (result, error) = await invoiceService.ConfirmAsync(
                RequiredStoreId, WorkBranchId, CurrentUserEmail, () => CurrentUserId, request, ct);
            if (error != null) return BadRequest(AppResponse<InvoiceConfirmResultDto>.Fail(error));
            return Ok(AppResponse<InvoiceConfirmResultDto>.Success(result!));
        }
        catch (InvalidOperationException ex)
        {
            return BadRequest(AppResponse<InvoiceConfirmResultDto>.Fail(ex.Message));
        }
        catch (DbUpdateException ex) when (!GlobalExceptionMiddleware.IsConcurrencyConflict(ex))
        {
            logger.LogWarning(ex, "AI invoice confirm save failed");
            return BadRequest(AppResponse<InvoiceConfirmResultDto>.Fail(
                "Không lưu được phiếu nhập (có thể đang tạo cùng lúc / bấm hai lần) — tải lại danh sách phiếu nhập rồi thử lại."));
        }
    }
}

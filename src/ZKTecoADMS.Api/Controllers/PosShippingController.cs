using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Api.Services.Shipping;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;

namespace ZKTecoADMS.Api.Controllers;

[ApiController]
[Route("api/pos/shipping")]
[Authorize]
public class PosShippingController(
    PosShippingService shipping,
    IModulePermissionService permissionService) : AuthenticatedControllerBase
{
    bool TryGetStoreId(out Guid storeId)
    {
        storeId = Guid.Empty;
        if (CurrentStoreId is { } sid && sid != Guid.Empty)
        {
            storeId = sid;
            return true;
        }
        return false;
    }

    [HttpGet("carriers")]
    [RequireModulePermission("PosShipping", ModulePermissionAction.View)]
    public ActionResult<AppResponse<object>> ListCarriers()
    {
        var items = ShippingCarrierCodes.All.Select(c => new
        {
            code = c,
            name = ShippingCarrierCodes.DisplayName(c),
        });
        return Ok(AppResponse<object>.Success(items));
    }

    /// <summary>Danh sách hãng đã bật — dùng dropdown bán hàng / tạo vận đơn.</summary>
    [HttpGet("enabled")]
    [RequireModulePermission("PosShipping", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> ListEnabled(CancellationToken ct)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<object>.Fail("Thiếu cửa hàng"));
        var list = await shipping.ListSettingsAsync(storeId, ct);
        var items = list.Where(x => x.Enabled).Select(x => new
        {
            code = x.CarrierCode,
            name = x.DisplayName,
        });
        return Ok(AppResponse<object>.Success(items));
    }

    [HttpGet("settings")]
    [RequireModulePermission("PosShipping", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<ShippingCarrierSettingDto>>>> GetSettings(
        CancellationToken ct)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<List<ShippingCarrierSettingDto>>.Fail("Thiếu cửa hàng"));
        var list = await shipping.ListSettingsAsync(storeId, ct);
        // Link webhook đầy đủ (kèm mã bí mật) — chủ shop dán vào trang quản lý của hãng.
        var baseUrl = $"{Request.Scheme}://{Request.Host}/api/webhooks/shipping";
        list = list.Select(x => string.IsNullOrWhiteSpace(x.WebhookSecret)
            ? x
            : x with
            {
                WebhookUrl = x.CarrierCode == ShippingCarrierCodes.ViettelPost
                    ? $"{baseUrl}/viettelpost"
                    : $"{baseUrl}/{x.CarrierCode.ToLowerInvariant()}?hash={x.WebhookSecret}",
            }).ToList();
        return Ok(AppResponse<List<ShippingCarrierSettingDto>>.Success(list));
    }

    async Task<bool> CanEditShippingSettingsAsync(CancellationToken ct)
    {
        if (IsAdmin) return true;
        if (await permissionService.HasPermissionAsync(
                CurrentUserId, CurrentUserRole, CurrentStoreId,
                "PosShipping", ModulePermissionAction.Edit, ct))
            return true;
        if (await permissionService.HasPermissionAsync(
                CurrentUserId, CurrentUserRole, CurrentStoreId,
                "PosSell", ModulePermissionAction.Edit, ct))
            return true;
        return await permissionService.HasPermissionAsync(
            CurrentUserId, CurrentUserRole, CurrentStoreId,
            "SettingsHub", ModulePermissionAction.Edit, ct);
    }

    [HttpPut("settings")]
    public async Task<ActionResult<AppResponse<ShippingCarrierSettingDto>>> UpsertSettings(
        [FromBody] ShippingCarrierSettingUpsertRequest req, CancellationToken ct)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<ShippingCarrierSettingDto>.Fail("Thiếu cửa hàng"));
        if (!await CanEditShippingSettingsAsync(ct))
            return StatusCode(StatusCodes.Status403Forbidden,
                AppResponse<ShippingCarrierSettingDto>.Fail(
                    "Tài khoản không có quyền sửa cấu hình vận chuyển (cần Sửa Đơn vị giao hàng / POS / thiết lập)."));
        try
        {
            var dto = await shipping.UpsertAsync(storeId, req, CurrentUserEmail, ct);
            return Ok(AppResponse<ShippingCarrierSettingDto>.Success(dto));
        }
        catch (Exception ex)
        {
            return BadRequest(AppResponse<ShippingCarrierSettingDto>.Fail(ex.Message));
        }
    }

    [HttpPost("quote")]
    [RequireModulePermission("PosShipping", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<ShippingQuoteResult>>> Quote(
        [FromBody] ShippingQuoteRequest req, CancellationToken ct)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<ShippingQuoteResult>.Fail("Thiếu cửa hàng"));
        var result = await shipping.QuoteAsync(storeId, req, ct);
        return Ok(AppResponse<ShippingQuoteResult>.Success(result));
    }

    /// <summary>So sánh cước tất cả hãng đã bật + ước tính kiện từ sản phẩm.</summary>
    [HttpPost("compare")]
    [RequireModulePermission("PosShipping", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<ShippingCompareResult>>> Compare(
        [FromBody] ShippingCompareRequest req, CancellationToken ct)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<ShippingCompareResult>.Fail("Thiếu cửa hàng"));
        try
        {
            var result = await shipping.CompareForOrderAsync(storeId, req, ct);
            return Ok(AppResponse<ShippingCompareResult>.Success(result));
        }
        catch (Exception ex)
        {
            return BadRequest(AppResponse<ShippingCompareResult>.Fail(ex.Message));
        }
    }

    [HttpGet("orders/{orderId:guid}/package")]
    [RequireModulePermission("PosShipping", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<ShippingPackageEstimate>>> EstimatePackage(
        Guid orderId,
        [FromQuery] int? weightGrams = null,
        [FromQuery] int? lengthCm = null,
        [FromQuery] int? widthCm = null,
        [FromQuery] int? heightCm = null,
        CancellationToken ct = default)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<ShippingPackageEstimate>.Fail("Thiếu cửa hàng"));
        var result = await shipping.EstimatePackageForOrderAsync(
            storeId, orderId, weightGrams, lengthCm, widthCm, heightCm, ct);
        return Ok(AppResponse<ShippingPackageEstimate>.Success(result));
    }

    [HttpPost("shipments")]
    [RequireModulePermission("PosShipping", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<ShippingCreateResult>>> CreateShipment(
        [FromBody] ShippingCreateRequest req, CancellationToken ct)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<ShippingCreateResult>.Fail("Thiếu cửa hàng"));
        var result = await shipping.CreateForOrderAsync(storeId, req, CurrentUserEmail, ct);
        return Ok(AppResponse<ShippingCreateResult>.Success(result));
    }

    [HttpGet("viettelpost/addresses")]
    [RequireModulePermission("PosShipping", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> ListViettelPostAddresses(
        [FromQuery] string level = "province",
        [FromQuery] int? parentId = null,
        CancellationToken ct = default)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<object>.Fail("Thiếu cửa hàng"));
        var items = await shipping.ListViettelPostAddressesAsync(storeId, level, parentId, ct);
        return Ok(AppResponse<object>.Success(items));
    }

    [HttpGet("shipments/{orderId:guid}/label")]
    [RequireModulePermission("PosShipping", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<ShippingLabelResult>>> GetShipmentLabel(
        Guid orderId, CancellationToken ct)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<ShippingLabelResult>.Fail("Thiếu cửa hàng"));
        var result = await shipping.GetShipmentLabelAsync(storeId, orderId, ct);
        // Link nội bộ (nhãn GHTK) → tuyệt đối để máy bán mở trực tiếp.
        if (result.LabelUrl != null && result.LabelUrl.StartsWith('/'))
            result = result with { LabelUrl = $"{Request.Scheme}://{Request.Host}{result.LabelUrl}" };
        return Ok(AppResponse<ShippingLabelResult>.Success(result));
    }

    [HttpPost("shipments/{orderId:guid}/cancel")]
    [RequireModulePermission("PosShipping", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<ShippingCancelResult>>> CancelShipment(
        Guid orderId, [FromBody] CancelShipmentRequest? req, CancellationToken ct)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<ShippingCancelResult>.Fail("Thiếu cửa hàng"));
        var result = await shipping.CancelShipmentAsync(
            storeId, orderId, req?.Note, CurrentUserEmail, ct);
        return Ok(AppResponse<ShippingCancelResult>.Success(result));
    }

    /// <summary>Shop xác nhận đã nhận lại hàng hoàn → nhập kho lại, hủy đơn bán.</summary>
    [HttpPost("shipments/{orderId:guid}/confirm-return")]
    [RequireModulePermission("PosShipping", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> ConfirmReturn(
        Guid orderId, [FromBody] ConfirmReturnRequest? req, CancellationToken ct)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<object>.Fail("Thiếu cửa hàng"));
        var (ok, msg) = await shipping.ConfirmReturnReceivedAsync(storeId, orderId, req?.Note, CurrentUserEmail, ct);
        return ok ? Ok(AppResponse<object>.Success(new { message = msg })) : BadRequest(AppResponse<object>.Fail(msg));
    }

    /// <summary>Đánh dấu hãng đã chuyển tiền COD (đối soát) cho các đơn.</summary>
    [HttpPost("cod-settle")]
    [RequireModulePermission("PosShipping", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> SettleCod(
        [FromBody] CodSettleRequest req, CancellationToken ct)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<object>.Fail("Thiếu cửa hàng"));
        var n = await shipping.MarkCodSettledAsync(storeId, req.OrderIds ?? [], req.Settled, CurrentUserEmail, ct);
        return Ok(AppResponse<object>.Success(new { updated = n }));
    }

    /// <summary>Hành trình vận đơn (nhật ký trạng thái) của một đơn.</summary>
    [HttpGet("shipments/{orderId:guid}/events")]
    [RequireModulePermission("PosShipping", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> ShipmentEvents(Guid orderId, CancellationToken ct)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<object>.Fail("Thiếu cửa hàng"));
        var items = await shipping.ListEventsAsync(storeId, orderId, ct);
        return Ok(AppResponse<object>.Success(items));
    }

    /// <summary>PDF nhãn GHTK qua link có chữ ký (máy bán mở bằng trình duyệt, không cần đăng nhập).</summary>
    [HttpGet("label-file/{orderId:guid}")]
    [AllowAnonymous]
    public async Task<IActionResult> LabelFile(Guid orderId, [FromQuery] long exp, [FromQuery] string? sig,
        CancellationToken ct)
    {
        var (pdf, err) = await shipping.DownloadSignedLabelAsync(orderId, exp, sig, ct);
        if (pdf == null) return BadRequest(err ?? "Không tải được nhãn");
        return File(pdf, "application/pdf", $"nhan-van-don-{orderId:N}.pdf");
    }

    /// <summary>Báo cáo vận chuyển: theo hãng, giao thất bại, hoàn hàng, hủy vận đơn, COD, lãi/lỗ ship.</summary>
    [HttpGet("report")]
    [RequireModulePermission("PosShipping", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<ShippingReport>>> Report(
        [FromQuery] DateTime? from, [FromQuery] DateTime? to, [FromQuery] string? carrier, CancellationToken ct)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<ShippingReport>.Fail("Thiếu cửa hàng"));
        var report = await shipping.BuildReportAsync(storeId, from, to, carrier, ct);
        return Ok(AppResponse<ShippingReport>.Success(report));
    }

    [HttpGet("report/excel")]
    [RequireModulePermission("PosShipping", ModulePermissionAction.View)]
    public async Task<IActionResult> ReportExcel(
        [FromQuery] DateTime? from, [FromQuery] DateTime? to, [FromQuery] string? carrier, CancellationToken ct)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<object>.Fail("Thiếu cửa hàng"));
        var r = await shipping.BuildReportAsync(storeId, from, to, carrier, ct);
        using var wb = new ClosedXML.Excel.XLWorkbook();

        var sum = wb.AddWorksheet("Theo hang");
        string[] sh =
        [
            "Hãng", "Vận đơn", "Đã giao", "Đang xử lý", "Đơn giao thất bại", "Lượt thất bại", "Đang hoàn",
            "Đã hoàn", "Đã hủy", "Tỉ lệ thành công (%)", "TG giao TB (giờ)", "Phí thu khách",
            "Cước shop chịu", "Lãi/lỗ ship", "COD đã giao", "COD chưa đối soát",
        ];
        for (var i = 0; i < sh.Length; i++) sum.Cell(1, i + 1).Value = sh[i];
        var row = 2;
        foreach (var c in r.ByCarrier.Append(r.Total))
        {
            object?[] v =
            [
                c.CarrierName, c.Shipments, c.Delivered, c.InProgress, c.FailedOrders, c.FailedAttempts,
                c.Returning, c.Returned, c.Cancelled, c.SuccessRate, c.AvgDeliveryHours, c.FeeCharged,
                c.CarrierCost, c.ShipProfit, c.CodDelivered, c.CodPending,
            ];
            for (var i = 0; i < v.Length; i++) sum.Cell(row, i + 1).Value = ClosedXML.Excel.XLCellValue.FromObject(v[i]);
            row++;
        }
        sum.Row(row - 1).Style.Font.Bold = true;
        ReportExcelLayout.FinishSheet(sum, 1);

        void Detail(string title, IReadOnlyList<ShippingReportRow> items)
        {
            var ws = wb.AddWorksheet(title);
            string[] h =
            [
                "Số HĐ", "Khách", "SĐT", "Hãng", "Mã vận đơn", "Gói", "Trạng thái", "Tạo vận đơn (UTC+7)",
                "Cập nhật", "Đã giao lúc", "Lần thất bại", "Lý do", "Hoàn về lúc", "Shop nhận hoàn",
                "Hủy lúc", "Phí thu khách", "Cước hãng", "Người trả cước", "COD", "Đối soát COD",
            ];
            for (var i = 0; i < h.Length; i++) ws.Cell(1, i + 1).Value = h[i];
            var rr = 2;
            static object? L(DateTime? d) => d?.AddHours(7);
            foreach (var x in items)
            {
                object?[] v =
                [
                    x.OrderNo, x.CustomerName, x.Phone, x.CarrierName, x.TrackingCode, x.ServiceName, x.StatusLabel,
                    L(x.ShippedAt), L(x.StatusAt), L(x.DeliveredAt), x.FailCount, x.Reason, L(x.ReturnedAt),
                    L(x.ReturnReceivedAt), L(x.CancelledAt), x.DeliveryFee, x.CarrierFee, x.FeePayer, x.CodAmount,
                    x.CodSettledAt == null ? "Chưa" : "Đã đối soát",
                ];
                for (var i = 0; i < v.Length; i++) ws.Cell(rr, i + 1).Value = ClosedXML.Excel.XLCellValue.FromObject(v[i]);
                rr++;
            }
            ws.SheetView.FreezeRows(1);
            ReportExcelLayout.FinishSheet(ws, 1);
        }

        Detail("Giao that bai", r.Failed);
        Detail("Hoan hang", r.Returns);
        Detail("Huy van don", r.Cancelled);
        Detail("Doi soat COD", r.Cod);
        Detail("Tat ca van don", r.All);

        using var stream = new MemoryStream();
        wb.SaveAs(stream);
        return File(stream.ToArray(),
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            $"POS_VanChuyen_{DateTime.Now:yyyyMMdd}.xlsx");
    }

    [HttpPost("shipments/{orderId:guid}/sync-tracking")]
    [RequireModulePermission("PosShipping", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<ShippingTrackingResult>>> SyncTracking(
        Guid orderId, CancellationToken ct)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<ShippingTrackingResult>.Fail("Thiếu cửa hàng"));
        var result = await shipping.SyncTrackingAsync(storeId, orderId, CurrentUserEmail, ct);
        return Ok(AppResponse<ShippingTrackingResult>.Success(result));
    }
}

public record CancelShipmentRequest(string? Note);

public record ConfirmReturnRequest(string? Note);

public record CodSettleRequest(List<Guid> OrderIds, bool Settled = true);

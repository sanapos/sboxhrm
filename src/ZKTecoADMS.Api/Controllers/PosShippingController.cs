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

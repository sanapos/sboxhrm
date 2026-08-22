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
    [RequireModulePermission("SettingsHub", ModulePermissionAction.View)]
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
    [RequireModulePermission("PosSell", ModulePermissionAction.View)]
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
    [RequireModulePermission("PosSell", ModulePermissionAction.View)]
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
                    "Tài khoản không có quyền sửa cấu hình vận chuyển (cần Sửa POS hoặc Sửa thiết lập)."));
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
    [RequireModulePermission("PosSell", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<ShippingQuoteResult>>> Quote(
        [FromBody] ShippingQuoteRequest req, CancellationToken ct)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<ShippingQuoteResult>.Fail("Thiếu cửa hàng"));
        var result = await shipping.QuoteAsync(storeId, req, ct);
        return Ok(AppResponse<ShippingQuoteResult>.Success(result));
    }

    [HttpPost("shipments")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<ShippingCreateResult>>> CreateShipment(
        [FromBody] ShippingCreateRequest req, CancellationToken ct)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<ShippingCreateResult>.Fail("Thiếu cửa hàng"));
        var result = await shipping.CreateForOrderAsync(storeId, req, CurrentUserEmail, ct);
        return Ok(AppResponse<ShippingCreateResult>.Success(result));
    }
}

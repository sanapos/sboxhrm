using Microsoft.AspNetCore.Mvc;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Api.Controllers;

[Route("api/store")]
public class StoreLicenseController(IRepository<Store> storeRepository) : AuthenticatedControllerBase
{
    /// <summary>
    /// Kiểm tra nhanh trạng thái license cửa hàng hiện tại (app gọi khi mở/resume).
    /// </summary>
    [HttpGet("license-status")]
    public async Task<ActionResult<AppResponse<object>>> GetLicenseStatus(CancellationToken ct)
    {
        var storeId = RequiredStoreId;
        var store = await storeRepository.GetByIdAsync(storeId, cancellationToken: ct);
        if (store == null)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy cửa hàng"));

        var expired = !store.IsActive || StoreLicenseHelper.IsExpired(store);
        return Ok(AppResponse<object>.Success(new
        {
            isExpired = expired,
            isActive = store.IsActive,
            expiryDate = store.ExpiryDate,
            message = expired ? StoreLicenseHelper.ExpiredMessage : null
        }));
    }
}

using Microsoft.AspNetCore.Mvc;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Api.Controllers;

[Route("api/store")]
public class StoreLicenseController(IRepository<Store> storeRepository) : AuthenticatedControllerBase
{
    /// <summary>
    /// Trạng thái gói dịch vụ của cửa hàng hiện tại: còn bao nhiêu ngày, hạn đến ngày nào, đang dùng thử hay không.
    /// App gọi khi mở / resume và khi mở màn Cài đặt.
    /// </summary>
    [HttpGet("license-status")]
    public async Task<ActionResult<AppResponse<object>>> GetLicenseStatus(CancellationToken ct)
    {
        var storeId = RequiredStoreId;
        var store = await storeRepository.GetByIdAsync(
            storeId, includeProperties: [nameof(Store.ServicePackage)], cancellationToken: ct);
        if (store == null)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy cửa hàng"));

        var expired = !store.IsActive || StoreLicenseHelper.IsExpired(store);

        // Hạn hiệu lực: ExpiryDate, hoặc cuối kỳ dùng thử khi cửa hàng chưa mua gói.
        // Endpoint cũ trả thẳng store.ExpiryDate nên cửa hàng đang dùng thử không thấy hạn nào.
        var expiry = StoreLicenseHelper.GetEffectiveExpiryDate(store);
        var onTrial = !store.ExpiryDate.HasValue
            && store.TrialStartDate.HasValue
            && store.TrialDays > 0;

        // Đếm theo ngày lịch: hết hạn hôm nay = còn 0 ngày, hôm qua = -1.
        int? daysLeft = expiry.HasValue
            ? (int)(expiry.Value.Date - DateTime.UtcNow.Date).TotalDays
            : null;

        return Ok(AppResponse<object>.Success(new
        {
            isExpired = expired,
            isActive = store.IsActive,
            expiryDate = store.ExpiryDate,
            effectiveExpiryDate = expiry,
            daysLeft,
            isTrial = onTrial,
            packageName = store.ServicePackage?.Name ?? LicenseTypeLabel(store.LicenseType),
            message = expired ? StoreLicenseHelper.ExpiredMessage : null
        }));
    }

    private static string LicenseTypeLabel(LicenseType type) => type switch
    {
        LicenseType.Basic => "Cơ bản",
        LicenseType.Advanced => "Nâng cao",
        LicenseType.Professional => "Chuyên nghiệp",
        _ => "SBOX",
    };
}

using ZKTecoADMS.Domain.Exceptions;
using Microsoft.AspNetCore.Authorization;
using System.Security.Claims;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Controllers.Base;

[Authorize]
public abstract class AuthenticatedControllerBase : ControllerBase
{
    protected Guid CurrentUserId => GetCurrentUserId();
    
    protected string CurrentUserRole => GetCurrentUserRole();

    protected Guid? EmployeeId => GetEmployeeId();
    
    protected Guid? ManagerId => GetManagerId();
    
    /// <summary>
    /// Lấy StoreId của user hiện tại từ JWT token
    /// </summary>
    protected Guid? CurrentStoreId => GetCurrentStoreId();
    
    /// <summary>
    /// Lấy StoreId bắt buộc - throw exception nếu không có
    /// </summary>
    protected Guid RequiredStoreId => GetRequiredStoreId();

    protected bool IsAdmin => CurrentUserRole.Equals(nameof(Roles.Admin), StringComparison.OrdinalIgnoreCase)
        || CurrentUserRole.Equals(nameof(Roles.Director), StringComparison.OrdinalIgnoreCase)
        || CurrentUserRole.Equals(nameof(Roles.SuperAdmin), StringComparison.OrdinalIgnoreCase);
    
    protected bool IsManager => IsAdmin
        || CurrentUserRole.Equals(nameof(Roles.Manager), StringComparison.OrdinalIgnoreCase)
        || CurrentUserRole.Equals(nameof(Roles.DepartmentHead), StringComparison.OrdinalIgnoreCase)
        || CurrentUserRole.Equals(nameof(Roles.Agent), StringComparison.OrdinalIgnoreCase);
    
    protected bool IsEmployee => CurrentUserRole.Equals(nameof(Roles.Employee), StringComparison.OrdinalIgnoreCase);
    
    protected string? CurrentUserEmail => User.FindFirst(ClaimTypes.Email)?.Value;

    /// <summary>SuperAdmin được phép gia hạn vượt giới hạn 3 lần/shop.</summary>
    protected const string StoreRenewalBypassEmail = "sanapos.vn@gmail.com";

    protected const int MaxStoreRenewals = 3;

    protected bool CanBypassStoreRenewalLimit =>
        CurrentUserRole.Equals(nameof(Roles.SuperAdmin), StringComparison.OrdinalIgnoreCase)
        && string.Equals(CurrentUserEmail, StoreRenewalBypassEmail, StringComparison.OrdinalIgnoreCase);

    protected bool IsStoreRenewalLimitReached(int renewalCount) =>
        renewalCount >= MaxStoreRenewals && !CanBypassStoreRenewalLimit;

    /// <summary>Chỉ sanapos.vn@gmail.com — nhập số ngày gia hạn tùy ý.</summary>
    protected bool CanUseCustomStoreRenewalDays => CanBypassStoreRenewalLimit;

    protected bool TryValidateRenewalDays(int days, out string errorMessage)
    {
        if (days <= 0)
        {
            errorMessage = "Số ngày gia hạn phải lớn hơn 0";
            return false;
        }

        if (!StoreRenewalHelper.IsAllowedRenewalDays(days, CanUseCustomStoreRenewalDays))
        {
            errorMessage = StoreRenewalHelper.PresetOnlyMessage;
            return false;
        }

        errorMessage = string.Empty;
        return true;
    }

    protected bool IsCrossStoreNotificationUser =>
        CurrentUserRole.Equals(nameof(Roles.SuperAdmin), StringComparison.OrdinalIgnoreCase)
        || CurrentUserRole.Equals(nameof(Roles.Agent), StringComparison.OrdinalIgnoreCase);

    private Guid GetCurrentUserId()
    {
        var userIdClaim = User.FindFirst("id")?.Value ?? User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
        if (string.IsNullOrEmpty(userIdClaim) || !Guid.TryParse(userIdClaim, out var userId))
        {
            throw new UnauthorizedException("User ID not found in token.");
        }
        return userId;
    }
    
    private string GetCurrentUserRole()
    {
        var roleClaim = User.FindFirst(ClaimTypes.Role)?.Value;
        if (string.IsNullOrEmpty(roleClaim))
        {
            throw new UnauthorizedException("User role not found in token.");
        }
        return roleClaim;
    }

    private Guid? GetEmployeeId()
    {
        var employeeIdClaim = User.FindFirst(ClaimTypeNames.EmployeeId)?.Value;
        if (string.IsNullOrEmpty(employeeIdClaim) || !Guid.TryParse(employeeIdClaim, out var employeeId))
        {
            return null;
        }
        return employeeId;
    }

    private Guid? GetManagerId()
    {
        var managerIdClaim = User.FindFirst(ClaimTypeNames.ManagerId)?.Value;
        if (string.IsNullOrEmpty(managerIdClaim) || !Guid.TryParse(managerIdClaim, out var managerId))
        {
            return null;
        }
        return managerId;
    }
    
    protected Guid? GetCurrentStoreId()
    {
        var storeIdClaim = User.FindFirst(ClaimTypeNames.StoreId)?.Value;
        if (string.IsNullOrEmpty(storeIdClaim) || !Guid.TryParse(storeIdClaim, out var storeId))
        {
            return null;
        }
        return storeId;
    }
    
    private Guid GetRequiredStoreId()
    {
        var storeId = GetCurrentStoreId();
        if (!storeId.HasValue)
        {
            throw new UnauthorizedException("Store ID not found in token. User must belong to a store.");
        }
        return storeId.Value;
    }
} 
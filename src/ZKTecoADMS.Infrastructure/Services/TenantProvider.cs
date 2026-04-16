using System.Security.Claims;
using Microsoft.AspNetCore.Http;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Infrastructure.Services;

/// <summary>
/// Resolves the current tenant (store) from the authenticated user's JWT claims.
/// For background services or unauthenticated requests, returns null StoreId with IsSuperAccess=true.
/// </summary>
public class TenantProvider : ITenantProvider
{
    public Guid? StoreId { get; }
    public bool IsSuperAccess { get; }

    public TenantProvider(IHttpContextAccessor httpContextAccessor)
    {
        var user = httpContextAccessor.HttpContext?.User;
        
        if (user?.Identity?.IsAuthenticated != true)
        {
            // No authenticated user (background service, anonymous endpoint)
            StoreId = null;
            IsSuperAccess = true;
            return;
        }

        // Extract role
        var role = user.FindFirst(ClaimTypes.Role)?.Value;
        
        // SuperAdmin and Agent can see all tenants
        if (string.Equals(role, nameof(Roles.SuperAdmin), StringComparison.OrdinalIgnoreCase) ||
            string.Equals(role, nameof(Roles.Agent), StringComparison.OrdinalIgnoreCase))
        {
            StoreId = null;
            IsSuperAccess = true;
            return;
        }

        // Regular users: extract StoreId from JWT
        var storeIdClaim = user.FindFirst(ClaimTypeNames.StoreId)?.Value;
        if (!string.IsNullOrEmpty(storeIdClaim) && Guid.TryParse(storeIdClaim, out var storeId))
        {
            StoreId = storeId;
        }
        
        IsSuperAccess = false;
    }
}

using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Configuration;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Infrastructure.Services;

/// <summary>
/// Resolves the current tenant (store) from the authenticated user's JWT claims.
/// For background services or unauthenticated requests, returns null StoreId with IsSuperAccess=true.
/// </summary>
/// <remarks>
/// Đọc người dùng LÚC ĐƯỢC HỎI, không đọc một lần trong constructor. Lúc xác thực JWT (OnTokenValidated dùng
/// DbContext) request chưa có User: bản cũ chốt luôn «không đăng nhập → thấy mọi cửa hàng» cho cả request, nên
/// bộ lọc cửa hàng chung của EF tắt với mọi request đã đăng nhập. Giờ chỉ chốt sau khi đã có người dùng.
/// Tắt nhanh khi cần (về cách cũ): cấu hình <c>Tenancy:EnforceRequestFilter=false</c>
/// (biến môi trường <c>Tenancy__EnforceRequestFilter=false</c>).
/// </remarks>
public class TenantProvider : ITenantProvider
{
    private readonly IHttpContextAccessor _http;
    private (Guid? StoreId, bool Super)? _resolved;

    public Guid? StoreId => Current().StoreId;
    public bool IsSuperAccess => Current().Super;

    public TenantProvider(IHttpContextAccessor httpContextAccessor, IConfiguration? configuration = null)
    {
        _http = httpContextAccessor;
        var enforce = configuration?.GetValue<bool?>("Tenancy:EnforceRequestFilter") ?? true;
        // Cách cũ: chốt theo trạng thái lúc tạo (thường là lúc xác thực, chưa có User).
        if (!enforce) _resolved = Read(httpContextAccessor.HttpContext, legacy: true) ?? (null, true);
    }

    private (Guid? StoreId, bool Super) Current()
    {
        if (_resolved is { } done) return done;
        // Chưa có người dùng (đang xác thực, endpoint công khai, dịch vụ nền) → chưa chốt, hỏi lại lần sau.
        if (Read(_http.HttpContext, legacy: false) is not { } now) return (null, true);
        _resolved = now;
        return now;
    }

    /// <summary>null = chưa có người dùng đã đăng nhập.</summary>
    private static (Guid? StoreId, bool Super)? Read(HttpContext? context, bool legacy)
    {
        var user = context?.User;
        if (user?.Identity?.IsAuthenticated != true)
            return null;

        // Endpoint không đòi đăng nhập (công khai / AllowAnonymous: đặt món QR, webhook, làm mới token…) tự lọc
        // cửa hàng trong mã của nó — giữ quyền thấy mọi cửa hàng như trước dù app có gửi kèm token.
        if (!legacy && context!.GetEndpoint() is { } endpoint
            && (endpoint.Metadata.GetMetadata<IAllowAnonymous>() != null
                || endpoint.Metadata.GetMetadata<IAuthorizeData>() == null))
            return (null, true);

        // SuperAdmin and Agent can see all tenants
        var role = user.FindFirst(ClaimTypes.Role)?.Value;
        if (string.Equals(role, nameof(Roles.SuperAdmin), StringComparison.OrdinalIgnoreCase) ||
            string.Equals(role, nameof(Roles.Agent), StringComparison.OrdinalIgnoreCase))
            return (null, true);

        // Regular users: extract StoreId from JWT
        var storeIdClaim = user.FindFirst(ClaimTypeNames.StoreId)?.Value;
        return !string.IsNullOrEmpty(storeIdClaim) && Guid.TryParse(storeIdClaim, out var storeId)
            ? (storeId, false)
            : (null, false);
    }
}

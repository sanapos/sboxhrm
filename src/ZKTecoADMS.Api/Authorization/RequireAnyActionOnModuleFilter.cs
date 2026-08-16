using System.Security.Claims;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;

namespace ZKTecoADMS.Api.Authorization;

public sealed class RequireAnyActionOnModuleFilter(
    string module,
    ModulePermissionAction action1,
    ModulePermissionAction action2,
    IModulePermissionService permissionService) : IAsyncAuthorizationFilter
{
    public async Task OnAuthorizationAsync(AuthorizationFilterContext context)
    {
        var user = context.HttpContext.User;
        if (user.Identity?.IsAuthenticated != true)
            return;

        if (!TryGetUserContext(user, out var userId, out var role, out var storeId))
        {
            context.Result = new ObjectResult(AppResponse<object>.Fail("Không xác định được người dùng."))
            {
                StatusCode = StatusCodes.Status401Unauthorized
            };
            return;
        }

        var ct = context.HttpContext.RequestAborted;
        if (await permissionService.HasPermissionAsync(userId, role, storeId, module, action1, ct))
            return;
        if (await permissionService.HasPermissionAsync(userId, role, storeId, module, action2, ct))
            return;

        context.Result = new ObjectResult(
            AppResponse<object>.Fail($"Tài khoản không có quyền thao tác module {module}."))
        {
            StatusCode = StatusCodes.Status403Forbidden
        };
    }

    private static bool TryGetUserContext(
        ClaimsPrincipal user,
        out Guid userId,
        out string role,
        out Guid? storeId)
    {
        userId = Guid.Empty;
        role = user.FindFirst(ClaimTypes.Role)?.Value ?? "";
        storeId = null;

        var userIdClaim = user.FindFirst("id")?.Value
                          ?? user.FindFirst(ClaimTypes.NameIdentifier)?.Value;
        if (string.IsNullOrEmpty(userIdClaim) || !Guid.TryParse(userIdClaim, out userId))
            return false;

        var storeClaim = user.FindFirst("storeId")?.Value;
        if (!string.IsNullOrEmpty(storeClaim) && Guid.TryParse(storeClaim, out var sid))
            storeId = sid;

        return !string.IsNullOrEmpty(role);
    }
}

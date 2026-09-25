using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Controllers;
using Microsoft.AspNetCore.Mvc.Filters;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers.Filters;

/// <summary>
/// Tài khoản Agent (đại lý) được miễn quyền module (ModulePermissionDefaults.IsSuperRole)
/// và không bị lọc theo cửa hàng (TenantProvider) — nên phải khóa phạm vi ở đây:
/// chỉ API cổng đại lý / đăng nhập / thông báo / hồ sơ cá nhân, API công khai,
/// và API thiết bị thuộc cửa hàng do chính đại lý quản lý. Còn lại → 403.
/// </summary>
public class AgentApiScopeFilter(ZKTecoDbContext db) : IAsyncActionFilter
{
    private static readonly HashSet<string> AgentPortalControllers = new(StringComparer.OrdinalIgnoreCase)
    {
        "Agent",
        "AgentRegistration",
        "Auth",
        "Notifications",
        "ActiveAnnouncements",
    };

    /// <summary>Chỉ các action hồ sơ cá nhân (đổi tên, đổi mật khẩu) của AccountsController.</summary>
    private const string AccountsController = "Accounts";

    private static readonly HashSet<string> DeviceControllers = new(StringComparer.OrdinalIgnoreCase)
    {
        "Devices",
        "DeviceCommands",
        "DeviceCommandStatus",
        "DeviceUsers",
        "Biometric",
    };

    public async Task OnActionExecutionAsync(ActionExecutingContext context, ActionExecutionDelegate next)
    {
        var user = context.HttpContext.User;
        if (user.Identity?.IsAuthenticated != true
            || !user.IsInRole(nameof(Roles.Agent))
            || user.IsInRole(nameof(Roles.SuperAdmin))
            || context.ActionDescriptor.EndpointMetadata.OfType<IAllowAnonymous>().Any())
        {
            await next();
            return;
        }

        var descriptor = context.ActionDescriptor as ControllerActionDescriptor;
        var controller = descriptor?.ControllerName ?? "";

        if (AgentPortalControllers.Contains(controller)
            || (controller.Equals(AccountsController, StringComparison.OrdinalIgnoreCase)
                && (descriptor?.AttributeRouteInfo?.Template ?? "").Contains("/profile", StringComparison.OrdinalIgnoreCase)))
        {
            await next();
            return;
        }

        if (DeviceControllers.Contains(controller)
            && await DeviceBelongsToAgentAsync(context, controller, user))
        {
            await next();
            return;
        }

        context.Result = new ObjectResult(
            AppResponse<object>.Fail("Tài khoản đại lý không có quyền truy cập chức năng này."))
        {
            StatusCode = StatusCodes.Status403Forbidden
        };
    }

    private async Task<bool> DeviceBelongsToAgentAsync(
        ActionExecutingContext context, string controller, ClaimsPrincipal user)
    {
        var deviceId = FindDeviceId(context, controller);
        if (deviceId == null) return false;

        var userIdRaw = user.FindFirst("id")?.Value ?? user.FindFirst(ClaimTypes.NameIdentifier)?.Value;
        if (!Guid.TryParse(userIdRaw, out var userId)) return false;

        var ct = context.HttpContext.RequestAborted;
        return await db.Devices.IgnoreQueryFilters().AnyAsync(d =>
            d.Id == deviceId.Value
            && db.Stores.Any(s => s.Id == d.StoreId
                && db.Agents.IgnoreQueryFilters().Any(a => a.Id == s.AgentId && a.UserId == userId)), ct);
    }

    /// <summary>Thiết bị đích: route <c>deviceId</c>, route <c>id</c> của DevicesController,
    /// hoặc thuộc tính <c>DeviceId</c> trong body.</summary>
    private static Guid? FindDeviceId(ActionExecutingContext context, string controller)
    {
        var routeKey = controller.Equals("Devices", StringComparison.OrdinalIgnoreCase) ? "id" : null;
        foreach (var key in new[] { "deviceId", routeKey })
        {
            if (key != null
                && context.RouteData.Values.TryGetValue(key, out var raw)
                && Guid.TryParse(raw?.ToString(), out var fromRoute))
                return fromRoute;
        }

        foreach (var arg in context.ActionArguments.Values)
        {
            var prop = arg?.GetType().GetProperty("DeviceId");
            if (prop?.GetValue(arg) is Guid fromBody && fromBody != Guid.Empty)
                return fromBody;
        }
        return null;
    }
}

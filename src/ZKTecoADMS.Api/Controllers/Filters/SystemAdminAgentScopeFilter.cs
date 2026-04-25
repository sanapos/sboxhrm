using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Controllers;
using Microsoft.AspNetCore.Mvc.Filters;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Controllers.Filters;

/// <summary>
/// Áp dụng cho SystemAdminController khi role = Agent: chỉ cho phép một số action
/// đọc dữ liệu thuộc phạm vi của đại lý đó. Các action khác → 403.
/// SuperAdmin được bỏ qua hoàn toàn.
/// </summary>
public class SystemAdminAgentScopeFilter : IAsyncActionFilter
{
    private static readonly HashSet<string> AgentAllowedActions = new(StringComparer.OrdinalIgnoreCase)
    {
        "GetDashboard",
        "GetAllStores",
        "GetStoreById",
        "GetAllUsers",
        "GetAllDevices",
    };

    public async Task OnActionExecutionAsync(ActionExecutingContext context, ActionExecutionDelegate next)
    {
        var user = context.HttpContext.User;
        var isSuperAdmin = user.IsInRole(nameof(Roles.SuperAdmin));
        var isAgent = user.IsInRole(nameof(Roles.Agent));

        if (!isSuperAdmin && isAgent)
        {
            var actionName = (context.ActionDescriptor as ControllerActionDescriptor)?.ActionName ?? string.Empty;
            if (!AgentAllowedActions.Contains(actionName))
            {
                context.Result = new ObjectResult(
                    AppResponse<object>.Fail("Tài khoản đại lý không có quyền truy cập chức năng này."))
                {
                    StatusCode = StatusCodes.Status403Forbidden
                };
                return;
            }
        }

        await next();
    }
}

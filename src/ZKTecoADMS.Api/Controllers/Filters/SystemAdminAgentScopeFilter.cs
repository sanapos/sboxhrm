using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Controllers;
using Microsoft.AspNetCore.Mvc.Filters;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Controllers.Filters;

/// <summary>
/// Áp dụng cho SystemAdminController khi role = Agent → 403 mọi action.
/// Các action system-admin trả dữ liệu toàn hệ thống (kể cả mật khẩu người dùng), không lọc
/// theo đại lý; cổng đại lý dùng <c>/api/agent/*</c> (đã lọc theo cửa hàng của đại lý).
/// SuperAdmin được bỏ qua hoàn toàn.
/// </summary>
public class SystemAdminAgentScopeFilter : IAsyncActionFilter
{
    private static readonly HashSet<string> AgentAllowedActions = new(StringComparer.OrdinalIgnoreCase);

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

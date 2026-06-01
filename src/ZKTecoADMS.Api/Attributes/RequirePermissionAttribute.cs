using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;
using Microsoft.EntityFrameworkCore;
using System.Security.Claims;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Attributes;

/// <summary>
/// Attribute để kiểm tra quyền truy cập module
/// </summary>
[AttributeUsage(AttributeTargets.Method | AttributeTargets.Class, AllowMultiple = true)]
public class RequirePermissionAttribute : Attribute, IAsyncAuthorizationFilter
{
    public string Module { get; }
    public PermissionAction Action { get; }

    public RequirePermissionAttribute(string module, PermissionAction action)
    {
        Module = module;
        Action = action;
    }

    public async Task OnAuthorizationAsync(AuthorizationFilterContext context)
    {
        var user = context.HttpContext.User;
        
        if (!user.Identity?.IsAuthenticated ?? true)
        {
            context.Result = new UnauthorizedObjectResult(
                AppResponse<object>.Error("Unauthorized"));
            return;
        }

        // Lấy role từ claims
        var roleClaim = user.FindFirst(ClaimTypes.Role)?.Value;
        
        if (string.IsNullOrEmpty(roleClaim))
        {
            context.Result = new ForbidResult();
            return;
        }

        // Admin/SuperAdmin/Agent có toàn quyền
        if (roleClaim is "Admin" or "SuperAdmin" or "Agent")
        {
            return; // Cho phép
        }

        var storeIdClaim = user.FindFirst("storeId")?.Value;
        if (string.IsNullOrEmpty(storeIdClaim))
        {
            context.Result = new ForbidResult();
            return;
        }

        var storeId = Guid.Parse(storeIdClaim);
        var userIdClaim = user.FindFirst(ClaimTypes.NameIdentifier)?.Value;
        Guid? userId = !string.IsNullOrEmpty(userIdClaim) ? Guid.Parse(userIdClaim) : null;

        // Lấy DbContext từ DI
        var dbContext = context.HttpContext.RequestServices.GetRequiredService<ZKTecoDbContext>();

        // 1. Kiểm tra quyền theo Role (RolePermission)
        var rolePermission = await dbContext.RolePermissions
            .Include(rp => rp.Permission)
            .FirstOrDefaultAsync(rp => 
                rp.RoleName == roleClaim && 
                rp.Permission.Module == Module &&
                (rp.StoreId == storeId || rp.StoreId == null) &&
                rp.IsActive);

        bool hasRolePermission = rolePermission != null && CheckAction(rolePermission.CanView, rolePermission.CanCreate, rolePermission.CanEdit, rolePermission.CanDelete, rolePermission.CanExport, rolePermission.CanApprove);

        // 2. Kiểm tra quyền theo Phòng ban (DepartmentPermission) - OR với RolePermission.
        // Phải dùng biểu thức EF-translatable (không gọi CheckAction trong LINQ).
        bool hasDeptPermission = false;
        if (userId.HasValue)
        {
            var deptBase = dbContext.DepartmentPermissions
                .Where(dp =>
                    dp.UserId == userId.Value &&
                    dp.Permission!.Module == Module &&
                    (dp.StoreId == storeId || dp.StoreId == null) &&
                    dp.IsActive);

            hasDeptPermission = Action switch
            {
                PermissionAction.View => await deptBase.AnyAsync(dp => dp.CanView),
                PermissionAction.Create => await deptBase.AnyAsync(dp => dp.CanCreate),
                PermissionAction.Edit => await deptBase.AnyAsync(dp => dp.CanEdit),
                PermissionAction.Delete => await deptBase.AnyAsync(dp => dp.CanDelete),
                PermissionAction.Export => await deptBase.AnyAsync(dp => dp.CanExport),
                PermissionAction.Approve => await deptBase.AnyAsync(dp => dp.CanApprove),
                _ => false
            };
        }

        if (!hasRolePermission && !hasDeptPermission)
        {
            context.Result = new ObjectResult(
                AppResponse<object>.Error($"Bạn không có quyền {GetActionDisplayName(Action)} trong module {Module}"))
            {
                StatusCode = StatusCodes.Status403Forbidden
            };
        }
    }

    private static string GetActionDisplayName(PermissionAction action) => action switch
    {
        PermissionAction.View => "xem",
        PermissionAction.Create => "tạo mới",
        PermissionAction.Edit => "chỉnh sửa",
        PermissionAction.Delete => "xóa",
        PermissionAction.Export => "xuất báo cáo",
        PermissionAction.Approve => "duyệt",
        _ => "truy cập"
    };

    private bool CheckAction(bool canView, bool canCreate, bool canEdit, bool canDelete, bool canExport, bool canApprove) => Action switch
    {
        PermissionAction.View => canView,
        PermissionAction.Create => canCreate,
        PermissionAction.Edit => canEdit,
        PermissionAction.Delete => canDelete,
        PermissionAction.Export => canExport,
        PermissionAction.Approve => canApprove,
        _ => false
    };
}

/// <summary>
/// Loại hành động trong permission
/// </summary>
public enum PermissionAction
{
    View,
    Create,
    Edit,
    Delete,
    Export,
    Approve
}

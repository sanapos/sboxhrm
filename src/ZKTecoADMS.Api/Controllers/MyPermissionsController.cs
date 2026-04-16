using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.DTOs.Permissions;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// Controller cho user lấy quyền hiệu lực của chính mình.
/// Tách riêng khỏi PermissionManagementController (AtLeastAdmin) để Employee/Manager truy cập được.
/// </summary>
[ApiController]
[Route("api/permission-management")]
[Authorize(Policy = PolicyNames.AtLeastEmployee)]
public class MyPermissionsController(ZKTecoDbContext context) : AuthenticatedControllerBase
{
    /// <summary>
    /// Lấy quyền hiệu lực của user hiện tại (role + department permissions)
    /// </summary>
    [HttpGet("my-permissions")]
    public async Task<ActionResult<AppResponse<List<ModulePermissionDto>>>> GetMyEffectivePermissions()
    {
        var roleClaim = User.FindFirst(System.Security.Claims.ClaimTypes.Role)?.Value ?? "";
        var storeId = CurrentStoreId;

        // SuperAdmin/Agent/Admin có toàn quyền
        if (roleClaim is "SuperAdmin" or "Agent" or "Admin")
        {
            var allModules = await context.Permissions
                .OrderBy(p => p.DisplayOrder)
                .Select(p => new ModulePermissionDto
                {
                    PermissionId = p.Id,
                    Module = p.Module,
                    ModuleDisplayName = p.ModuleDisplayName,
                    DisplayOrder = p.DisplayOrder,
                    CanView = true, CanCreate = true, CanEdit = true,
                    CanDelete = true, CanExport = true, CanApprove = true
                })
                .ToListAsync();
            return Ok(AppResponse<List<ModulePermissionDto>>.Success(allModules));
        }

        // 1. Lấy quyền theo Role
        var rolePermissions = await context.RolePermissions
            .Include(rp => rp.Permission)
            .Where(rp => rp.RoleName == roleClaim &&
                         (rp.StoreId == storeId || rp.StoreId == null) &&
                         rp.IsActive)
            .ToListAsync();

        // 2. Lấy quyền theo Department (override)
        var userId = CurrentUserId;
        var deptPermissions = await context.DepartmentPermissions
            .Include(dp => dp.Permission)
            .Where(dp => dp.UserId == userId &&
                         (dp.StoreId == storeId || dp.StoreId == null) &&
                         dp.IsActive)
            .ToListAsync();

        // 3. Merge: role permissions + department permissions (OR logic)
        var allPermissionModules = await context.Permissions
            .OrderBy(p => p.DisplayOrder)
            .ToListAsync();

        var result = allPermissionModules.Select(module =>
        {
            var rolePerm = rolePermissions.FirstOrDefault(rp => rp.PermissionId == module.Id);
            var deptPerm = deptPermissions.FirstOrDefault(dp => dp.PermissionId == module.Id);

            return new ModulePermissionDto
            {
                PermissionId = module.Id,
                Module = module.Module,
                ModuleDisplayName = module.ModuleDisplayName,
                DisplayOrder = module.DisplayOrder,
                CanView = (rolePerm?.CanView ?? false) || (deptPerm?.CanView ?? false),
                CanCreate = (rolePerm?.CanCreate ?? false) || (deptPerm?.CanCreate ?? false),
                CanEdit = (rolePerm?.CanEdit ?? false) || (deptPerm?.CanEdit ?? false),
                CanDelete = (rolePerm?.CanDelete ?? false) || (deptPerm?.CanDelete ?? false),
                CanExport = (rolePerm?.CanExport ?? false) || (deptPerm?.CanExport ?? false),
                CanApprove = (rolePerm?.CanApprove ?? false) || (deptPerm?.CanApprove ?? false),
            };
        }).ToList();

        return Ok(AppResponse<List<ModulePermissionDto>>.Success(result));
    }
}

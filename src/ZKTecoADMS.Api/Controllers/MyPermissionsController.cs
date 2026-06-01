using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Authorization;
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
        if (ModulePermissionDefaults.IsSuperRole(roleClaim))
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

        // 1. Đồng bộ role permissions: tự thêm module mới còn thiếu cho role hiện tại
        var allPermissionModules = await context.Permissions
            .OrderBy(p => p.DisplayOrder)
            .ToListAsync();

        await EnsureRolePermissionsCompleteAsync(roleClaim, storeId, allPermissionModules);

        // 2. Lấy quyền theo Role
        var rolePermissions = await context.RolePermissions
            .Include(rp => rp.Permission)
            .Where(rp => rp.RoleName == roleClaim &&
                         (rp.StoreId == storeId || rp.StoreId == null) &&
                         rp.IsActive)
            .ToListAsync();

        // 3. Lấy quyền theo Department (override)
        var userId = CurrentUserId;
        var deptPermissions = await context.DepartmentPermissions
            .Include(dp => dp.Permission)
            .Where(dp => dp.UserId == userId &&
                         (dp.StoreId == storeId || dp.StoreId == null) &&
                         dp.IsActive)
            .ToListAsync();

        // 4. Merge: role permissions + department permissions (OR logic)

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

    private async Task EnsureRolePermissionsCompleteAsync(string roleName, Guid? storeId, List<ZKTecoADMS.Domain.Entities.Permission> allModules)
    {
        if (string.IsNullOrWhiteSpace(roleName) || allModules.Count == 0)
            return;

        var existingPermissionIds = await context.RolePermissions
            .Where(rp => rp.RoleName == roleName && (rp.StoreId == storeId || rp.StoreId == null) && rp.IsActive)
            .Select(rp => rp.PermissionId)
            .ToListAsync();

        var existingSet = existingPermissionIds.ToHashSet();
        var missingModules = allModules.Where(m => !existingSet.Contains(m.Id)).ToList();
        if (missingModules.Count == 0)
            return;

        foreach (var module in missingModules)
        {
            var (canView, canCreate, canEdit, canDelete, canExport, canApprove) =
                ModulePermissionDefaults.Get(roleName, module.Module);
            context.RolePermissions.Add(new ZKTecoADMS.Domain.Entities.RolePermission
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                RoleName = roleName,
                RoleDisplayName = GetRoleDisplayName(roleName),
                PermissionId = module.Id,
                CanView = canView,
                CanCreate = canCreate,
                CanEdit = canEdit,
                CanDelete = canDelete,
                CanExport = canExport,
                CanApprove = canApprove,
                IsActive = true
            });
        }

        await context.SaveChangesAsync();
    }

    private static string GetRoleDisplayName(string roleName) => roleName.ToLower() switch
    {
        "admin" => "Quản trị viên",
        "director" => "Giám đốc",
        "accountant" => "Kế toán",
        "departmenthead" => "Trưởng phòng",
        "manager" => "Quản lý",
        "employee" => "Nhân viên",
        "user" => "Người dùng",
        _ => roleName
    };
}

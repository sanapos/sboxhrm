using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Attributes;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Authorization;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.DTOs.Permissions;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// Controller Ä‘á»ƒ quáº£n lÃ½ phÃ¢n quyá»n theo role
/// </summary>
[ApiController]
[Route("api/permission-management")]
[Authorize(Policy = PolicyNames.AtLeastAdmin)]
public class PermissionManagementController(
    ZKTecoDbContext context,
    ILogger<PermissionManagementController> logger) : AuthenticatedControllerBase
{
    private static readonly string[] SystemRoles =
        ["Admin", "Director", "Accountant", "DepartmentHead", "Manager", "Employee", "User"];

    #region Get Permissions

    /// <summary>
    /// Láº¥y táº¥t cáº£ permissions cá»§a má»™t role
    /// </summary>
    [HttpGet("by-role")]
    [RequirePermission("Role", PermissionAction.View)]
    [RequireModulePermission("Role", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<RolePermissionGroupDto>>> GetPermissionsByRole([FromQuery] string roleName)
    {
        var permissions = await context.RolePermissions
            .Include(p => p.Permission)
            .Where(p => p.StoreId == RequiredStoreId && p.RoleName == roleName)
            .OrderBy(p => p.Permission.DisplayOrder)
            .ToListAsync();

        var allModules = await context.Permissions.OrderBy(p => p.DisplayOrder).ToListAsync();

        if (permissions.Count == 0)
        {
            // Táº¡o permissions máº·c Ä‘á»‹nh náº¿u chÆ°a cÃ³
            permissions = await CreateDefaultPermissionsForRole(roleName, allModules);
        }
        else
        {
            // Kiá»ƒm tra module má»›i Ä‘Æ°á»£c thÃªm sau khi role Ä‘Ã£ cÃ³ permissions
            var existingPermissionIds = permissions.Select(p => p.PermissionId).ToHashSet();
            var missingModules = allModules.Where(m => !existingPermissionIds.Contains(m.Id)).ToList();
            if (missingModules.Count > 0)
            {
                var newEntries = new List<RolePermission>();
                foreach (var module in missingModules)
                {
                    var (canView, canCreate, canEdit, canDelete, canExport, canApprove) = GetDefaultPermissions(roleName, module.Module);
                    newEntries.Add(new RolePermission
                    {
                        Id = Guid.NewGuid(),
                        StoreId = RequiredStoreId,
                        RoleName = roleName,
                        RoleDisplayName = GetRoleDisplayName(roleName),
                        PermissionId = module.Id,
                        CanView = canView,
                        CanCreate = canCreate,
                        CanEdit = canEdit,
                        CanDelete = canDelete,
                        CanExport = canExport,
                        CanApprove = canApprove
                    });
                }
                context.RolePermissions.AddRange(newEntries);
                await context.SaveChangesAsync();
                // Reload Ä‘á»ƒ cÃ³ Ä‘áº§y Ä‘á»§ navigation props
                permissions = await context.RolePermissions
                    .Include(p => p.Permission)
                    .Where(p => p.StoreId == RequiredStoreId && p.RoleName == roleName)
                    .OrderBy(p => p.Permission.DisplayOrder)
                    .ToListAsync();
            }
        }

        var modulePermissions = permissions.Select(p => new ModulePermissionDto
        {
            PermissionId = p.PermissionId,
            Module = p.Permission.Module,
            ModuleDisplayName = p.Permission.ModuleDisplayName,
            DisplayOrder = p.Permission.DisplayOrder,
            CanView = p.CanView,
            CanCreate = p.CanCreate,
            CanEdit = p.CanEdit,
            CanDelete = p.CanDelete,
            CanExport = p.CanExport,
            CanApprove = p.CanApprove
        }).ToList();

        var result = new RolePermissionGroupDto
        {
            RoleName = roleName,
            RoleDisplayName = GetRoleDisplayName(roleName),
            StoreId = RequiredStoreId,
            Permissions = modulePermissions,
            GrantedModuleCount = CountGrantedModules(modulePermissions)
        };

        return Ok(AppResponse<RolePermissionGroupDto>.Success(result));
    }

    /// <summary>
    /// Láº¥y táº¥t cáº£ permissions cá»§a store theo táº¥t cáº£ roles
    /// </summary>
    [HttpGet("all")]
    [RequirePermission("Role", PermissionAction.View)]
    [RequireModulePermission("Role", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<RolePermissionGroupDto>>>> GetAllPermissions()
    {
        var allModules = await context.Permissions.OrderBy(p => p.DisplayOrder).ToListAsync();

        // Pre-load all role permissions for the store in one query
        var allPermissions = await context.RolePermissions
            .Include(p => p.Permission)
            .Where(p => p.StoreId == RequiredStoreId)
            .ToListAsync();
        var permissionsByRole = allPermissions.GroupBy(p => p.RoleName)
            .ToDictionary(g => g.Key, g => g.ToList(), StringComparer.OrdinalIgnoreCase);

        var storeRoleNames = permissionsByRole.Keys.ToList();
        var roleOrder = SystemRoles
            .Select((name, index) => (name, index))
            .ToDictionary(x => x.name, x => x.index, StringComparer.OrdinalIgnoreCase);
        var allRoles = SystemRoles
            .Union(storeRoleNames, StringComparer.OrdinalIgnoreCase)
            .OrderBy(r => roleOrder.GetValueOrDefault(r, 900))
            .ThenBy(r => r, StringComparer.OrdinalIgnoreCase)
            .ToList();

        var result = new List<RolePermissionGroupDto>();

        foreach (var roleName in allRoles)
        {
            if (!permissionsByRole.TryGetValue(roleName, out var permissions) || permissions.Count == 0)
            {
                permissions = await CreateDefaultPermissionsForRole(roleName, allModules);
            }
            else
            {
                var existingPermissionIds = permissions.Select(p => p.PermissionId).ToHashSet();
                var missingModules = allModules.Where(m => !existingPermissionIds.Contains(m.Id)).ToList();
                if (missingModules.Count > 0)
                {
                    var newEntries = new List<RolePermission>();
                    foreach (var module in missingModules)
                    {
                        var (canView, canCreate, canEdit, canDelete, canExport, canApprove) = GetDefaultPermissions(roleName, module.Module);
                        newEntries.Add(new RolePermission
                        {
                            Id = Guid.NewGuid(),
                            StoreId = RequiredStoreId,
                            RoleName = roleName,
                            RoleDisplayName = GetRoleDisplayName(roleName),
                            PermissionId = module.Id,
                            CanView = canView,
                            CanCreate = canCreate,
                            CanEdit = canEdit,
                            CanDelete = canDelete,
                            CanExport = canExport,
                            CanApprove = canApprove
                        });
                    }
                    context.RolePermissions.AddRange(newEntries);
                    await context.SaveChangesAsync();
                    permissions = (await context.RolePermissions
                        .Include(p => p.Permission)
                        .Where(p => p.StoreId == RequiredStoreId && p.RoleName == roleName)
                        .ToListAsync());
                    permissionsByRole[roleName] = permissions;
                }
            }

            var modulePermissions = permissions.Select(p => new ModulePermissionDto
            {
                PermissionId = p.PermissionId,
                Module = p.Permission.Module,
                ModuleDisplayName = p.Permission.ModuleDisplayName,
                DisplayOrder = p.Permission.DisplayOrder,
                CanView = p.CanView,
                CanCreate = p.CanCreate,
                CanEdit = p.CanEdit,
                CanDelete = p.CanDelete,
                CanExport = p.CanExport,
                CanApprove = p.CanApprove
            }).OrderBy(p => p.DisplayOrder).ToList();

            var displayName = permissions.FirstOrDefault()?.RoleDisplayName;
            if (string.IsNullOrWhiteSpace(displayName))
                displayName = GetRoleDisplayName(roleName);

            result.Add(new RolePermissionGroupDto
            {
                RoleName = roleName,
                RoleDisplayName = displayName,
                StoreId = RequiredStoreId,
                Permissions = modulePermissions,
                GrantedModuleCount = CountGrantedModules(modulePermissions)
            });
        }

        return Ok(AppResponse<List<RolePermissionGroupDto>>.Success(result));
    }

    /// <summary>
    /// Xóa hoàn toàn một chức danh tùy chỉnh (không phải chức danh hệ thống).
    /// </summary>
    [HttpDelete("role/{roleName}")]
    [RequirePermission("Role", PermissionAction.Delete)]
    [RequireModulePermission("Role", ModulePermissionAction.Delete)]
    public async Task<ActionResult<AppResponse<bool>>> DeleteRole(string roleName)
    {
        if (SystemRoles.Contains(roleName, StringComparer.OrdinalIgnoreCase))
        {
            return BadRequest(AppResponse<bool>.Error("Không thể xóa chức danh mặc định của hệ thống"));
        }

        var existingPermissions = await context.RolePermissions
            .Where(p => p.StoreId == RequiredStoreId && p.RoleName == roleName)
            .ToListAsync();

        if (existingPermissions.Count == 0)
        {
            return NotFound(AppResponse<bool>.Error("Không tìm thấy chức danh"));
        }

        context.RolePermissions.RemoveRange(existingPermissions);
        await context.SaveChangesAsync();

        return Ok(AppResponse<bool>.Success(true));
    }

    /// <summary>
    /// Láº¥y danh sÃ¡ch modules cÃ³ thá»ƒ phÃ¢n quyá»n
    /// </summary>
    [HttpGet("modules")]
    [RequireModulePermission("Role", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<PermissionDto>>>> GetAvailableModules()
    {
        var modules = await context.Permissions
            .OrderBy(p => p.DisplayOrder)
            .Select(p => new PermissionDto
            {
                Id = p.Id,
                Module = p.Module,
                ModuleDisplayName = p.ModuleDisplayName,
                Description = p.Description,
                DisplayOrder = p.DisplayOrder
            })
            .ToListAsync();

        return Ok(AppResponse<List<PermissionDto>>.Success(modules));
    }

    #endregion

    #region Update Permission

    /// <summary>
    /// Cáº­p nháº­t permissions cá»§a má»™t role
    /// </summary>
    [HttpPut("role/{roleName}")]
    [RequirePermission("Role", PermissionAction.Edit)]
    [RequireModulePermission("Role", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<bool>>> UpdateRolePermissions(
        string roleName, 
        [FromBody] List<ModulePermissionRequest> request)
    {
        if (roleName.Equals("Admin", StringComparison.OrdinalIgnoreCase))
        {
            return BadRequest(AppResponse<bool>.Error("Không thể chỉnh sửa quyền của Admin"));
        }

        if (request == null || request.Count == 0)
        {
            return BadRequest(AppResponse<bool>.Error("Danh sách quyền trống"));
        }

        var permissionDefs = await context.Permissions.AsNoTracking().ToListAsync();
        var defById = permissionDefs.ToDictionary(p => p.Id);
        var defByModule = permissionDefs
            .GroupBy(p => p.Module, StringComparer.OrdinalIgnoreCase)
            .ToDictionary(g => g.Key, g => g.First(), StringComparer.OrdinalIgnoreCase);

        // Load all rows for this role/store scope (including inactive) to avoid unique-index violations on insert.
        var existingPermissions = await context.RolePermissions
            .Include(p => p.Permission)
            .AsTracking()
            .Where(p => (p.StoreId == RequiredStoreId || p.StoreId == null)
                        && p.RoleName == roleName)
            .ToListAsync();

        var updated = 0;
        foreach (var moduleRequest in request)
        {
            Guid permissionId = moduleRequest.PermissionId;
            if (!defById.ContainsKey(permissionId)
                && !string.IsNullOrWhiteSpace(moduleRequest.Module)
                && defByModule.TryGetValue(moduleRequest.Module.Trim(), out var byModule))
            {
                permissionId = byModule.Id;
            }

            if (!defById.ContainsKey(permissionId))
                continue;

            var moduleCode = defById[permissionId].Module;
            var matches = existingPermissions
                .Where(p => p.PermissionId == permissionId
                            || (p.Permission != null
                                && string.Equals(p.Permission.Module, moduleCode,
                                    StringComparison.OrdinalIgnoreCase)))
                .ToList();

            if (matches.Count > 0)
            {
                var primary = matches[0];
                primary.PermissionId = permissionId;
                primary.StoreId = RequiredStoreId;
                primary.IsActive = true;
                primary.CanView = moduleRequest.CanView;
                primary.CanCreate = moduleRequest.CanCreate;
                primary.CanEdit = moduleRequest.CanEdit;
                primary.CanDelete = moduleRequest.CanDelete;
                primary.CanExport = moduleRequest.CanExport;
                primary.CanApprove = moduleRequest.CanApprove;

                foreach (var duplicate in matches.Skip(1))
                {
                    context.RolePermissions.Remove(duplicate);
                    existingPermissions.Remove(duplicate);
                }

                updated++;
            }
            else
            {
                var newPermission = new RolePermission
                {
                    Id = Guid.NewGuid(),
                    StoreId = RequiredStoreId,
                    RoleName = roleName,
                    RoleDisplayName = GetRoleDisplayName(roleName),
                    PermissionId = permissionId,
                    CanView = moduleRequest.CanView,
                    CanCreate = moduleRequest.CanCreate,
                    CanEdit = moduleRequest.CanEdit,
                    CanDelete = moduleRequest.CanDelete,
                    CanExport = moduleRequest.CanExport,
                    CanApprove = moduleRequest.CanApprove,
                    IsActive = true
                };
                context.RolePermissions.Add(newPermission);
                existingPermissions.Add(newPermission);
                updated++;
            }
        }

        if (updated == 0)
        {
            return BadRequest(AppResponse<bool>.Error(
                "Không cập nhật được quyền — PermissionId không hợp lệ hoặc không khớp module"));
        }

        try
        {
            await context.SaveChangesAsync();
        }
        catch (DbUpdateException ex)
        {
            logger.LogWarning(ex, "Failed to save role permissions for {RoleName}", roleName);
            var inner = ex.InnerException?.Message ?? ex.Message;
            if (inner.Contains("duplicate", StringComparison.OrdinalIgnoreCase)
                || inner.Contains("UNIQUE", StringComparison.OrdinalIgnoreCase)
                || inner.Contains("unique", StringComparison.OrdinalIgnoreCase))
            {
                return BadRequest(AppResponse<bool>.Error(
                    "Trùng bản ghi phân quyền trong cơ sở dữ liệu. Vui lòng thử lại hoặc liên hệ quản trị."));
            }

            return BadRequest(AppResponse<bool>.Error($"Không lưu được phân quyền: {inner}"));
        }

        return Ok(AppResponse<bool>.Success(true));
    }

    /// <summary>
    /// Reset permissions cá»§a má»™t role vá» máº·c Ä‘á»‹nh
    /// </summary>
    [HttpPost("reset/{roleName}")]
    [RequirePermission("Role", PermissionAction.Edit)]
    [RequireModulePermission("Role", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<bool>>> ResetPermissions(string roleName)
    {
        if (roleName.Equals("Admin", StringComparison.OrdinalIgnoreCase))
        {
            return BadRequest(AppResponse<bool>.Error("KhÃ´ng thá»ƒ reset quyá»n cá»§a Admin"));
        }

        var existingPermissions = await context.RolePermissions
            .Where(p => (p.StoreId == RequiredStoreId || p.StoreId == null) && p.RoleName == roleName)
            .ToListAsync();

        context.RolePermissions.RemoveRange(existingPermissions);

        // Táº¡o permissions máº·c Ä‘á»‹nh
        var allModules = await context.Permissions.OrderBy(p => p.DisplayOrder).ToListAsync();
        await CreateDefaultPermissionsForRole(roleName, allModules);

        return Ok(AppResponse<bool>.Success(true));
    }

    #endregion

    #region Helper Methods

    private async Task<List<RolePermission>> CreateDefaultPermissionsForRole(string roleName, List<Permission> modules)
    {
        var newPermissions = new List<RolePermission>();

        foreach (var module in modules)
        {
            var (canView, canCreate, canEdit, canDelete, canExport, canApprove) = GetDefaultPermissions(roleName, module.Module);

            var newPermission = new RolePermission
            {
                Id = Guid.NewGuid(),
                StoreId = RequiredStoreId,
                RoleName = roleName,
                RoleDisplayName = GetRoleDisplayName(roleName),
                PermissionId = module.Id,
                CanView = canView,
                CanCreate = canCreate,
                CanEdit = canEdit,
                CanDelete = canDelete,
                CanExport = canExport,
                CanApprove = canApprove
            };
            newPermissions.Add(newPermission);
        }

        context.RolePermissions.AddRange(newPermissions);
        await context.SaveChangesAsync();

        // Reload with Permission included
        return await context.RolePermissions
            .Include(p => p.Permission)
            .Where(p => p.StoreId == RequiredStoreId && p.RoleName == roleName)
            .ToListAsync();
    }

    private static (bool canView, bool canCreate, bool canEdit, bool canDelete, bool canExport, bool canApprove)
        GetDefaultPermissions(string roleName, string module) =>
        ModulePermissionDefaults.Get(roleName, module);

    private static int CountGrantedModules(IEnumerable<ModulePermissionDto> permissions) =>
        permissions.Count(p =>
            p.CanView || p.CanCreate || p.CanEdit || p.CanDelete || p.CanExport || p.CanApprove);

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

    #endregion
}






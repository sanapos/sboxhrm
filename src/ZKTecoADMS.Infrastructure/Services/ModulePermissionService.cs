using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.Authorization;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.DTOs.Permissions;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Infrastructure.Services;

public class ModulePermissionService(ZKTecoDbContext db) : IModulePermissionService
{
    private IReadOnlyDictionary<string, ModulePermissionDto>? _requestCache;
    private (Guid UserId, string Role, Guid? StoreId) _cacheKey;

    public async Task<IReadOnlyDictionary<string, ModulePermissionDto>> GetEffectivePermissionsAsync(
        Guid userId,
        string role,
        Guid? storeId,
        CancellationToken cancellationToken = default)
    {
        if (_requestCache != null && _cacheKey == (userId, role, storeId))
            return _requestCache;

        var map = await LoadMapAsync(userId, role, storeId, cancellationToken);
        _cacheKey = (userId, role, storeId);
        _requestCache = map;
        return map;
    }

    public async Task<bool> HasPermissionAsync(
        Guid userId,
        string role,
        Guid? storeId,
        string module,
        ModulePermissionAction action,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(module))
            return true;

        if (ModulePermissionDefaults.IsSuperRole(role))
            return true;

        var map = await GetEffectivePermissionsAsync(userId, role, storeId, cancellationToken);
        if (map.TryGetValue(module, out var perm))
        {
            var granted = action switch
            {
                ModulePermissionAction.View => perm.CanView,
                ModulePermissionAction.Create => perm.CanCreate,
                ModulePermissionAction.Edit => perm.CanEdit,
                ModulePermissionAction.Delete => perm.CanDelete,
                ModulePermissionAction.Export => perm.CanExport,
                ModulePermissionAction.Approve => perm.CanApprove,
                _ => false
            };
            if (granted)
                return true;
        }

        return ModulePermissionImplicitGrants.TryGrant(module, action, map);
    }

    private async Task<IReadOnlyDictionary<string, ModulePermissionDto>> LoadMapAsync(
        Guid userId,
        string role,
        Guid? storeId,
        CancellationToken cancellationToken)
    {
        if (ModulePermissionDefaults.IsSuperRole(role))
        {
            var all = await db.Permissions
                .AsNoTracking()
                .OrderBy(p => p.DisplayOrder)
                .Select(p => new ModulePermissionDto
                {
                    PermissionId = p.Id,
                    Module = p.Module,
                    ModuleDisplayName = p.ModuleDisplayName,
                    DisplayOrder = p.DisplayOrder,
                    CanView = true,
                    CanCreate = true,
                    CanEdit = true,
                    CanDelete = true,
                    CanExport = true,
                    CanApprove = true
                })
                .ToListAsync(cancellationToken);
            return all.ToDictionary(p => p.Module, StringComparer.Ordinal);
        }

        var allModules = await db.Permissions.AsNoTracking().OrderBy(p => p.DisplayOrder).ToListAsync(cancellationToken);

        var rolePermissions = await db.RolePermissions
            .AsNoTracking()
            .Where(rp => rp.RoleName == role &&
                         (rp.StoreId == storeId || rp.StoreId == null) &&
                         rp.IsActive)
            .ToListAsync(cancellationToken);

        var deptPermissions = await db.DepartmentPermissions
            .AsNoTracking()
            .Where(dp => dp.UserId == userId &&
                         (dp.StoreId == storeId || dp.StoreId == null) &&
                         dp.IsActive)
            .ToListAsync(cancellationToken);

        var result = allModules.Select(module =>
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

        return result.ToDictionary(p => p.Module, StringComparer.Ordinal);
    }
}

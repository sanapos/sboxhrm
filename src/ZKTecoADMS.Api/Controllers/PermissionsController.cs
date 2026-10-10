using ZKTecoADMS.Api.Authorization;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Authorization;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.DTOs.Permissions;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
public class PermissionsController(ZKTecoDbContext context) : AuthenticatedControllerBase
{
    Task<bool> IsStoreOwnerAsync() =>
        context.Stores.AnyAsync(s => s.Id == CurrentStoreId && s.OwnerId == CurrentUserId);

    /// <summary>null = được sửa quyền của vai trò này (không tự nâng quyền mình / vai trò cao hơn).</summary>
    async Task<string?> DenyRoleEditAsync(string roleName) =>
        AccountRolePolicy.CanEditRole(CurrentUserRole, await IsStoreOwnerAsync(), roleName);

    /// <summary>Cửa hàng được thao tác: chỉ SuperAdmin chọn được cửa hàng khác (tránh ghi đè quyền cửa hàng người khác).</summary>
    Guid? ScopedStore(Guid? requested) =>
        CurrentUserRole.Equals("SuperAdmin", StringComparison.OrdinalIgnoreCase)
            ? requested ?? CurrentStoreId
            : CurrentStoreId;

    /// <summary>
    /// Lấy danh sách tất cả các module (permissions)
    /// </summary>
    [HttpGet("modules")]
    public async Task<ActionResult<AppResponse<List<PermissionDto>>>> GetAllModules()
    {
        var permissions = await context.Permissions
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

        return Ok(AppResponse<List<PermissionDto>>.Success(permissions));
    }

    /// <summary>
    /// Lấy danh sách các chức danh (roles) đã được cấu hình
    /// </summary>
    [HttpGet("roles")]
    [Authorize(Policy = PolicyNames.AtLeastAdmin)]
    [RequireModulePermission("Role", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<RoleDto>>>> GetRoles([FromQuery] Guid? storeId = null)
    {
        storeId = ScopedStore(storeId);

        var query = context.RolePermissions
            .Include(rp => rp.Store)
            .Where(rp => rp.StoreId == storeId)
            .AsQueryable();

        var roles = await query
            .GroupBy(rp => new { rp.RoleName, rp.RoleDisplayName, rp.StoreId, StoreName = rp.Store != null ? rp.Store.Name : null })
            .Select(g => new RoleDto
            {
                RoleName = g.Key.RoleName,
                RoleDisplayName = g.Key.RoleDisplayName,
                PermissionCount = g.Count(rp =>
                    rp.CanView || rp.CanCreate || rp.CanEdit || rp.CanDelete ||
                    rp.CanExport || rp.CanApprove),
                StoreId = g.Key.StoreId,
                StoreName = g.Key.StoreName
            })
            .ToListAsync();

        // Thêm các role mặc định nếu chưa có
        var defaultRoles = new List<(string name, string display)>
        {
            ("Admin", "Quản trị viên"),
            ("Director", "Giám đốc"),
            ("Accountant", "Kế toán"),
            ("DepartmentHead", "Trưởng phòng"),
            ("Manager", "Quản lý"),
            ("Employee", "Nhân viên"),
            ("Cashier", "Thu ngân"),
            ("Waiter", "Order"),
            ("User", "Người dùng")
        };

        foreach (var (name, display) in defaultRoles)
        {
            if (!roles.Any(r => r.RoleName == name && r.StoreId == storeId))
            {
                roles.Add(new RoleDto
                {
                    RoleName = name,
                    RoleDisplayName = display,
                    PermissionCount = 0,
                    StoreId = storeId,
                    StoreName = null
                });
            }
        }

        return Ok(AppResponse<List<RoleDto>>.Success(roles.OrderBy(r => r.RoleName).ToList()));
    }

    /// <summary>
    /// Lấy chi tiết quyền của một role
    /// </summary>
    [HttpGet("roles/{roleName}")]
    [Authorize(Policy = PolicyNames.AtLeastAdmin)]
    [RequireModulePermission("Role", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<RolePermissionGroupDto>>> GetRolePermissions(
        string roleName, 
        [FromQuery] Guid? storeId = null)
    {
        storeId = ScopedStore(storeId);

        var permissions = await context.Permissions
            .OrderBy(p => p.DisplayOrder)
            .ToListAsync();

        var rolePermissions = await context.RolePermissions
            .Include(rp => rp.Permission)
            .Include(rp => rp.Store)
            .Where(rp => rp.RoleName == roleName && rp.StoreId == storeId)
            .ToListAsync();

        // Auto-create default permissions if none exist for this role (theo mẫu của gói cửa hàng)
        if (rolePermissions.Count == 0)
        {
            var allowed = storeId is Guid sid0 ? await StoreModulesAsync(sid0) : null;
            var newPermissions = permissions.Select(p =>
            {
                var f = PermissionPresetCatalog.DefaultFlags(roleName, p.Module, allowed);
                var (canView, canCreate, canEdit, canDelete, canExport, canApprove) = (f.V, f.C, f.E, f.D, f.X, f.A);
                return new RolePermission
                {
                    Id = Guid.NewGuid(),
                    StoreId = storeId,
                    RoleName = roleName,
                    RoleDisplayName = GetDefaultRoleDisplayName(roleName),
                    PermissionId = p.Id,
                    CanView = canView,
                    CanCreate = canCreate,
                    CanEdit = canEdit,
                    CanDelete = canDelete,
                    CanExport = canExport,
                    CanApprove = canApprove
                };
            }).ToList();

            context.RolePermissions.AddRange(newPermissions);
            await context.SaveChangesAsync();

            rolePermissions = await context.RolePermissions
                .Include(rp => rp.Permission)
                .Include(rp => rp.Store)
                .Where(rp => rp.RoleName == roleName && rp.StoreId == storeId)
                .ToListAsync();
        }

        var modulePermissions = permissions.Select(p =>
        {
            var rp = rolePermissions.FirstOrDefault(x => x.PermissionId == p.Id);
            return new ModulePermissionDto
            {
                PermissionId = p.Id,
                Module = p.Module,
                ModuleDisplayName = p.ModuleDisplayName,
                DisplayOrder = p.DisplayOrder,
                CanView = rp?.CanView ?? false,
                CanCreate = rp?.CanCreate ?? false,
                CanEdit = rp?.CanEdit ?? false,
                CanDelete = rp?.CanDelete ?? false,
                CanExport = rp?.CanExport ?? false,
                CanApprove = rp?.CanApprove ?? false
            };
        }).ToList();

        var result = new RolePermissionGroupDto
        {
            RoleName = roleName,
            RoleDisplayName = rolePermissions.FirstOrDefault()?.RoleDisplayName ?? GetDefaultRoleDisplayName(roleName),
            StoreId = storeId,
            StoreName = rolePermissions.FirstOrDefault()?.Store?.Name,
            Permissions = modulePermissions,
            GrantedModuleCount = modulePermissions.Count(p =>
                p.CanView || p.CanCreate || p.CanEdit || p.CanDelete || p.CanExport || p.CanApprove)
        };

        return Ok(AppResponse<RolePermissionGroupDto>.Success(result));
    }

    /// <summary>
    /// Tạo hoặc cập nhật quyền cho một role
    /// </summary>
    [HttpPost("roles")]
    [Authorize(Policy = PolicyNames.AtLeastAdmin)]
    [RequireModulePermission("Role", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<RolePermissionGroupDto>>> CreateOrUpdateRolePermissions(
        [FromBody] CreateRolePermissionRequest request)
    {
        if (await DenyRoleEditAsync(request.RoleName) is { } deny)
            return StatusCode(StatusCodes.Status403Forbidden, AppResponse<RolePermissionGroupDto>.Fail(deny));
        request.StoreId = ScopedStore(request.StoreId);

        // Xóa các quyền cũ của role này (nếu có)
        var existingPermissions = await context.RolePermissions
            .Where(rp => rp.RoleName == request.RoleName && rp.StoreId == request.StoreId)
            .ToListAsync();

        context.RolePermissions.RemoveRange(existingPermissions);

        // Thêm quyền mới
        var newPermissions = request.Permissions.Select(p => new RolePermission
        {
            Id = Guid.NewGuid(),
            RoleName = request.RoleName,
            RoleDisplayName = request.RoleDisplayName,
            PermissionId = p.PermissionId,
            StoreId = request.StoreId,
            CanView = p.CanView,
            CanCreate = p.CanCreate,
            CanEdit = p.CanEdit,
            CanDelete = p.CanDelete,
            CanExport = p.CanExport,
            CanApprove = p.CanApprove,
            IsActive = true,
            CreatedAt = DateTime.UtcNow,
            CreatedBy = CurrentUserId.ToString()
        }).ToList();

        await context.RolePermissions.AddRangeAsync(newPermissions);
        await context.SaveChangesAsync();

        // Trả về kết quả
        return await GetRolePermissions(request.RoleName, request.StoreId);
    }

    /// <summary>
    /// Xóa một role và tất cả quyền của nó
    /// </summary>
    [HttpDelete("roles/{roleName}")]
    [Authorize(Policy = PolicyNames.AtLeastAdmin)]
    [RequireModulePermission("Role", ModulePermissionAction.Delete)]
    public async Task<ActionResult<AppResponse<bool>>> DeleteRole(
        string roleName, 
        [FromQuery] Guid? storeId = null)
    {
        if (await DenyRoleEditAsync(roleName) is { } deny)
            return StatusCode(StatusCodes.Status403Forbidden, AppResponse<bool>.Fail(deny));
        storeId = ScopedStore(storeId);

        var permissions = await context.RolePermissions
            .Where(rp => rp.RoleName == roleName && rp.StoreId == storeId)
            .ToListAsync();

        if (!permissions.Any())
        {
            return NotFound(AppResponse<bool>.Error("Không tìm thấy role"));
        }

        context.RolePermissions.RemoveRange(permissions);
        await context.SaveChangesAsync();

        return Ok(AppResponse<bool>.Success(true));
    }

    // ══════════ MẪU PHÂN QUYỀN (HRM / POS / HRM + POS) ══════════

    public record PresetAssignment(string RoleName, string PresetId);
    public record ApplyPresetsRequest(List<PresetAssignment> Assignments);

    static PermissionPresetPackage? ParsePackage(string? raw) => (raw ?? "").Trim().ToLowerInvariant() switch
    {
        "hrm" => PermissionPresetPackage.Hrm,
        "pos" => PermissionPresetPackage.Pos,
        "full" => PermissionPresetPackage.Full,
        _ => null,
    };

    static string PackageCode(PermissionPresetPackage p) => p switch
    {
        PermissionPresetPackage.Hrm => "hrm",
        PermissionPresetPackage.Pos => "pos",
        _ => "full",
    };

    async Task<HashSet<string>> StoreModulesAsync(Guid storeId) =>
        (await ZKTecoADMS.Infrastructure.Helpers.StorePackageHelper.ResolveAllowedModulesAsync(context, storeId))
            .ToHashSet(StringComparer.OrdinalIgnoreCase);

    /// <summary>Danh sách mẫu + gói nhận diện của cửa hàng + mẫu mặc định cho từng vai trò.</summary>
    [HttpGet("presets")]
    public async Task<ActionResult<AppResponse<object>>> GetPresets([FromQuery] string? package = null)
    {
        var storeId = CurrentStoreId;
        var allowed = storeId is Guid sid ? await StoreModulesAsync(sid) : [];
        var detected = PermissionPresetCatalog.Detect(allowed);
        var chosen = ParsePackage(package) ?? detected;
        var presets = PermissionPresetCatalog.List(chosen).Select(p =>
        {
            var built = PermissionPresetCatalog.Build(p.Id);
            var granted = built.Keys.Count(m => PermissionPresetCatalog.FlagsFor(built, m, allowed).Any);
            return new
            {
                id = p.Id,
                roleName = p.RoleName,
                extraRoles = p.ExtraRoles ?? [],
                title = p.Title,
                description = p.Description,
                grantedModules = granted,
                superRole = ModulePermissionDefaults.IsSuperRole(p.RoleName),
            };
        }).ToList();
        return Ok(AppResponse<object>.Success(new
        {
            detectedPackage = PackageCode(detected),
            package = PackageCode(chosen),
            packages = new[] { PermissionPresetPackage.Hrm, PermissionPresetPackage.Pos, PermissionPresetPackage.Full }
                .Select(x => new { code = PackageCode(x), label = PermissionPresetCatalog.PackageLabel(x) }),
            defaults = PermissionPresetCatalog.Defaults(chosen),
            presets,
        }));
    }

    /// <summary>Xem trước quyền của một mẫu (đã lọc theo gói cửa hàng) — cùng dạng với quyền của vai trò.</summary>
    [HttpGet("presets/{presetId}")]
    public async Task<ActionResult<AppResponse<RolePermissionGroupDto>>> GetPreset(string presetId)
    {
        var preset = PermissionPresetCatalog.Find(presetId);
        if (preset == null) return NotFound(AppResponse<RolePermissionGroupDto>.Fail("Không tìm thấy mẫu phân quyền"));
        var allowed = CurrentStoreId is Guid sid ? await StoreModulesAsync(sid) : [];
        var built = PermissionPresetCatalog.Build(preset.Id);
        var modules = await context.Permissions.AsNoTracking().OrderBy(p => p.DisplayOrder).ToListAsync();
        var list = modules.Select(m =>
        {
            var f = PermissionPresetCatalog.FlagsFor(built, m.Module, allowed);
            return new ModulePermissionDto
            {
                PermissionId = m.Id, Module = m.Module, ModuleDisplayName = m.ModuleDisplayName, DisplayOrder = m.DisplayOrder,
                CanView = f.V, CanCreate = f.C, CanEdit = f.E, CanDelete = f.D, CanExport = f.X, CanApprove = f.A,
            };
        }).ToList();
        return Ok(AppResponse<RolePermissionGroupDto>.Success(new RolePermissionGroupDto
        {
            RoleName = preset.RoleName,
            RoleDisplayName = preset.Title,
            StoreId = CurrentStoreId,
            Permissions = list,
            GrantedModuleCount = list.Count(x => x.CanView || x.CanCreate || x.CanEdit || x.CanDelete || x.CanExport || x.CanApprove),
        }));
    }

    /// <summary>Áp dụng mẫu cho một hoặc nhiều vai trò của cửa hàng (ghi đè quyền hiện có của vai trò đó).</summary>
    [HttpPost("presets/apply")]
    [Authorize(Policy = PolicyNames.AtLeastAdmin)]
    [RequireModulePermission("Role", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> ApplyPresets([FromBody] ApplyPresetsRequest request)
    {
        if (CurrentStoreId is not Guid storeId)
            return BadRequest(AppResponse<object>.Fail("Không xác định được cửa hàng"));
        if (request.Assignments == null || request.Assignments.Count == 0)
            return BadRequest(AppResponse<object>.Fail("Chưa chọn vai trò nào"));

        var allowed = await StoreModulesAsync(storeId);
        var modules = await context.Permissions.AsNoTracking().ToListAsync();
        var applied = new List<object>();
        foreach (var a in request.Assignments)
        {
            var preset = PermissionPresetCatalog.Find(a.PresetId);
            if (preset == null)
                return BadRequest(AppResponse<object>.Fail($"Mẫu «{a.PresetId}» không tồn tại"));
            if (!preset.FitsRole(a.RoleName))
                return BadRequest(AppResponse<object>.Fail($"Mẫu «{preset.Title}» dành cho vai trò {preset.RoleName}"));
            if (a.RoleName.Equals("Admin", StringComparison.OrdinalIgnoreCase))
                continue; // chủ cửa hàng luôn toàn quyền
            if (await DenyRoleEditAsync(a.RoleName) is { } deny)
                return StatusCode(StatusCodes.Status403Forbidden, AppResponse<object>.Fail($"{a.RoleName}: {deny}"));

            var built = PermissionPresetCatalog.Build(preset.Id);
            var old = await context.RolePermissions.AsTracking()
                .Where(rp => rp.RoleName == a.RoleName && rp.StoreId == storeId)
                .ToListAsync();
            context.RolePermissions.RemoveRange(old);
            var rows = modules.Select(m =>
            {
                var f = PermissionPresetCatalog.FlagsFor(built, m.Module, allowed);
                return new RolePermission
                {
                    Id = Guid.NewGuid(),
                    RoleName = a.RoleName,
                    RoleDisplayName = preset.RoleName.Equals(a.RoleName, StringComparison.OrdinalIgnoreCase)
                        ? preset.Title
                        : GetDefaultRoleDisplayName(a.RoleName),
                    PermissionId = m.Id,
                    StoreId = storeId,
                    CanView = f.V, CanCreate = f.C, CanEdit = f.E, CanDelete = f.D, CanExport = f.X, CanApprove = f.A,
                    IsActive = true,
                    CreatedAt = DateTime.UtcNow,
                    CreatedBy = "Preset:" + preset.Id,
                };
            }).ToList();
            await context.RolePermissions.AddRangeAsync(rows);
            applied.Add(new { roleName = a.RoleName, presetId = preset.Id, title = preset.Title,
                granted = rows.Count(r => r.CanView || r.CanCreate || r.CanEdit || r.CanDelete || r.CanExport || r.CanApprove) });
        }
        await context.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(new { applied }));
    }

    /// <summary>
    /// Kiểm tra quyền của user hiện tại cho một module
    /// </summary>
    [HttpGet("check/{module}")]
    public async Task<ActionResult<AppResponse<ModulePermissionDto>>> CheckPermission(string module)
    {
        var userRole = CurrentUserRole;
        var userStoreId = CurrentStoreId;

        var permission = await context.Permissions
            .FirstOrDefaultAsync(p => p.Module == module);

        if (permission == null)
        {
            return NotFound(AppResponse<ModulePermissionDto>.Error($"Module {module} không tồn tại"));
        }

        var rolePermission = await context.RolePermissions
            .FirstOrDefaultAsync(rp => 
                rp.RoleName == userRole && 
                rp.PermissionId == permission.Id &&
                (rp.StoreId == userStoreId || rp.StoreId == null));

        var result = new ModulePermissionDto
        {
            PermissionId = permission.Id,
            Module = permission.Module,
            ModuleDisplayName = permission.ModuleDisplayName,
            DisplayOrder = permission.DisplayOrder,
            CanView = rolePermission?.CanView ?? (userRole == "Admin"),
            CanCreate = rolePermission?.CanCreate ?? (userRole == "Admin"),
            CanEdit = rolePermission?.CanEdit ?? (userRole == "Admin"),
            CanDelete = rolePermission?.CanDelete ?? (userRole == "Admin"),
            CanExport = rolePermission?.CanExport ?? (userRole == "Admin"),
            CanApprove = rolePermission?.CanApprove ?? (userRole == "Admin" || userRole == "Manager")
        };

        return Ok(AppResponse<ModulePermissionDto>.Success(result));
    }

    /// <summary>
    /// Lấy tất cả quyền của user hiện tại
    /// </summary>
    [HttpGet("my-permissions")]
    public async Task<ActionResult<AppResponse<RolePermissionGroupDto>>> GetMyPermissions()
    {
        // Quyền của chính mình — gọi thẳng (không qua kiểm tra quản trị của GET roles/{roleName}).
        return await GetRolePermissions(CurrentUserRole, CurrentStoreId);
    }

    private string GetDefaultRoleDisplayName(string roleName) => roleName switch
    {
        "Admin" => "Quản trị viên",
        "Director" => "Giám đốc",
        "Accountant" => "Kế toán",
        "DepartmentHead" => "Trưởng phòng",
        "Manager" => "Quản lý",
        "Employee" => "Nhân viên",
        "Cashier" => "Thu ngân",
        "Waiter" => "Order",
        "User" => "Người dùng",
        _ => roleName
    };

}

using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Controllers.Base;
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
    public async Task<ActionResult<AppResponse<List<RoleDto>>>> GetRoles([FromQuery] Guid? storeId = null)
    {
        // Auto-resolve storeId from current user if not provided
        if (!storeId.HasValue)
        {
            storeId = CurrentStoreId;
        }

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
                PermissionCount = g.Count(),
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
    public async Task<ActionResult<AppResponse<RolePermissionGroupDto>>> GetRolePermissions(
        string roleName, 
        [FromQuery] Guid? storeId = null)
    {
        // Auto-resolve storeId from current user if not provided
        if (!storeId.HasValue)
        {
            storeId = CurrentStoreId;
        }

        var permissions = await context.Permissions
            .OrderBy(p => p.DisplayOrder)
            .ToListAsync();

        var rolePermissions = await context.RolePermissions
            .Include(rp => rp.Permission)
            .Include(rp => rp.Store)
            .Where(rp => rp.RoleName == roleName && rp.StoreId == storeId)
            .ToListAsync();

        // Auto-create default permissions if none exist for this role
        if (rolePermissions.Count == 0)
        {
            var newPermissions = permissions.Select(p =>
            {
                var (canView, canCreate, canEdit, canDelete, canExport, canApprove) = GetDefaultPermissions(roleName, p.Module);
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

        var result = new RolePermissionGroupDto
        {
            RoleName = roleName,
            RoleDisplayName = rolePermissions.FirstOrDefault()?.RoleDisplayName ?? GetDefaultRoleDisplayName(roleName),
            StoreId = storeId,
            StoreName = rolePermissions.FirstOrDefault()?.Store?.Name,
            Permissions = permissions.Select(p =>
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
            }).ToList()
        };

        return Ok(AppResponse<RolePermissionGroupDto>.Success(result));
    }

    /// <summary>
    /// Tạo hoặc cập nhật quyền cho một role
    /// </summary>
    [HttpPost("roles")]
    [Authorize(Policy = PolicyNames.AtLeastAdmin)]
    public async Task<ActionResult<AppResponse<RolePermissionGroupDto>>> CreateOrUpdateRolePermissions(
        [FromBody] CreateRolePermissionRequest request)
    {
        // Auto-resolve storeId from current user if not provided
        if (!request.StoreId.HasValue)
        {
            request.StoreId = CurrentStoreId;
        }

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
    public async Task<ActionResult<AppResponse<bool>>> DeleteRole(
        string roleName, 
        [FromQuery] Guid? storeId = null)
    {
        // Auto-resolve storeId from current user if not provided
        if (!storeId.HasValue)
        {
            storeId = CurrentStoreId;
        }

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
        var userRole = CurrentUserRole;
        var userStoreId = CurrentStoreId;

        return await GetRolePermissions(userRole, userStoreId);
    }

    private string GetDefaultRoleDisplayName(string roleName) => roleName switch
    {
        "Admin" => "Quản trị viên",
        "Director" => "Giám đốc",
        "Accountant" => "Kế toán",
        "DepartmentHead" => "Trưởng phòng",
        "Manager" => "Quản lý",
        "Employee" => "Nhân viên",
        "User" => "Người dùng",
        _ => roleName
    };

    private static (bool canView, bool canCreate, bool canEdit, bool canDelete, bool canExport, bool canApprove)
        GetDefaultPermissions(string roleName, string module)
    {
        return roleName.ToLower() switch
        {
            "admin" => (true, true, true, true, true, true),

            "director" => module.ToLower() switch
            {
                "settings" or "device" or "geofence" or "deviceuser" => (true, false, false, false, false, false),
                "store" or "role" or "usermanagement" or "departmentpermission" => (true, false, false, false, true, false),
                _ => (true, true, true, true, true, true)
            },

            "accountant" => module.ToLower() switch
            {
                "salary" or "payslip" or "allowance" or "insurance" or "tax" or "advance"
                    or "transaction" or "cashtransaction" or "bankaccount" or "benefit"
                    => (true, true, true, true, true, false),
                "report" => (true, false, false, false, true, false),
                "employee" or "attendance" => (true, false, false, false, true, false),
                "dashboard" or "leave" or "shift" or "holiday" or "overtime" or "notification"
                    => (true, false, false, false, false, false),
                _ => (false, false, false, false, false, false)
            },

            "departmenthead" => module.ToLower() switch
            {
                "employee" or "attendance" or "leave" or "shift" or "overtime"
                    or "attendancecorrection" or "workshedule" or "shiftswap"
                    or "task" or "kpi" or "hrdocument"
                    => (true, true, true, false, true, true),
                "notification" or "communication" => (true, true, false, false, false, false),
                "report" or "salary" or "payslip" => (true, false, false, false, true, false),
                "dashboard" or "allowance" or "holiday" or "insurance" or "advance"
                    or "shifttemplate" or "shiftsalarylevel" or "benefit" or "asset"
                    or "orgchart" or "department"
                    => (true, false, false, false, false, false),
                _ => (false, false, false, false, false, false)
            },

            "manager" => module.ToLower() switch
            {
                "settings" or "store" or "role" => (true, false, false, false, false, false),
                _ => (true, true, true, false, true, true)
            },

            "employee" => module.ToLower() switch
            {
                "dashboard" or "attendance" or "payslip" or "shift" or "notification"
                    => (true, false, false, false, false, false),
                "leave" or "shiftswap" or "attendancecorrection" or "overtime"
                    => (true, true, false, false, false, false),
                "task" => (true, false, true, false, false, false),
                "fieldcheckin" => (true, true, true, false, false, false),
                _ => (false, false, false, false, false, false)
            },

            "user" => module.ToLower() switch
            {
                "dashboard" => (true, false, false, false, false, false),
                _ => (false, false, false, false, false, false)
            },

            _ => (false, false, false, false, false, false)
        };
    }

}

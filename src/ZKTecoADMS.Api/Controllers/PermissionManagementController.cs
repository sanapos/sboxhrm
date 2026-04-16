using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Attributes;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.DTOs.Permissions;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// Controller để quản lý phân quyền theo role
/// </summary>
[ApiController]
[Route("api/permission-management")]
[Authorize(Policy = PolicyNames.AtLeastAdmin)]
public class PermissionManagementController(ZKTecoDbContext context) : AuthenticatedControllerBase
{
    #region Get Permissions

    /// <summary>
    /// Lấy tất cả permissions của một role
    /// </summary>
    [HttpGet("by-role")]
    [RequirePermission("Role", PermissionAction.View)]
    public async Task<ActionResult<AppResponse<RolePermissionGroupDto>>> GetPermissionsByRole([FromQuery] string roleName)
    {
        var permissions = await context.RolePermissions
            .Include(p => p.Permission)
            .Where(p => p.StoreId == RequiredStoreId && p.RoleName == roleName)
            .OrderBy(p => p.Permission.DisplayOrder)
            .ToListAsync();

        if (permissions.Count == 0)
        {
            // Tạo permissions mặc định nếu chưa có
            var allModules = await context.Permissions.OrderBy(p => p.DisplayOrder).ToListAsync();
            permissions = await CreateDefaultPermissionsForRole(roleName, allModules);
        }

        var result = new RolePermissionGroupDto
        {
            RoleName = roleName,
            RoleDisplayName = GetRoleDisplayName(roleName),
            StoreId = RequiredStoreId,
            Permissions = permissions.Select(p => new ModulePermissionDto
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
            }).ToList()
        };

        return Ok(AppResponse<RolePermissionGroupDto>.Success(result));
    }

    /// <summary>
    /// Lấy tất cả permissions của store theo tất cả roles
    /// </summary>
    [HttpGet("all")]
    [RequirePermission("Role", PermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<RolePermissionGroupDto>>>> GetAllPermissions()
    {
        var allRoles = new[] { "Admin", "Director", "Accountant", "DepartmentHead", "Manager", "Employee", "User" };
        var allModules = await context.Permissions.OrderBy(p => p.DisplayOrder).ToListAsync();

        // Pre-load all role permissions for the store in one query
        var allPermissions = await context.RolePermissions
            .Include(p => p.Permission)
            .Where(p => p.StoreId == RequiredStoreId && allRoles.Contains(p.RoleName))
            .ToListAsync();
        var permissionsByRole = allPermissions.GroupBy(p => p.RoleName)
            .ToDictionary(g => g.Key, g => g.ToList());

        var result = new List<RolePermissionGroupDto>();

        foreach (var roleName in allRoles)
        {
            if (!permissionsByRole.TryGetValue(roleName, out var permissions) || permissions.Count == 0)
            {
                permissions = await CreateDefaultPermissionsForRole(roleName, allModules);
            }

            result.Add(new RolePermissionGroupDto
            {
                RoleName = roleName,
                RoleDisplayName = GetRoleDisplayName(roleName),
                StoreId = RequiredStoreId,
                Permissions = permissions.Select(p => new ModulePermissionDto
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
                }).OrderBy(p => p.DisplayOrder).ToList()
            });
        }

        return Ok(AppResponse<List<RolePermissionGroupDto>>.Success(result));
    }

    /// <summary>
    /// Lấy danh sách modules có thể phân quyền
    /// </summary>
    [HttpGet("modules")]
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
    /// Cập nhật permissions của một role
    /// </summary>
    [HttpPut("role/{roleName}")]
    [RequirePermission("Role", PermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<bool>>> UpdateRolePermissions(
        string roleName, 
        [FromBody] List<ModulePermissionRequest> request)
    {
        // Không cho phép chỉnh sửa permission của Admin
        if (roleName.Equals("Admin", StringComparison.OrdinalIgnoreCase))
        {
            return BadRequest(AppResponse<bool>.Error("Không thể chỉnh sửa quyền của Admin"));
        }

        var existingPermissions = await context.RolePermissions
            .AsTracking()
            .Where(p => p.StoreId == RequiredStoreId && p.RoleName == roleName)
            .ToListAsync();

        foreach (var moduleRequest in request)
        {
            var existing = existingPermissions.FirstOrDefault(p => p.PermissionId == moduleRequest.PermissionId);
            if (existing != null)
            {
                existing.CanView = moduleRequest.CanView;
                existing.CanCreate = moduleRequest.CanCreate;
                existing.CanEdit = moduleRequest.CanEdit;
                existing.CanDelete = moduleRequest.CanDelete;
                existing.CanExport = moduleRequest.CanExport;
                existing.CanApprove = moduleRequest.CanApprove;
            }
            else
            {
                // Tạo mới nếu chưa có
                var newPermission = new RolePermission
                {
                    Id = Guid.NewGuid(),
                    StoreId = RequiredStoreId,
                    RoleName = roleName,
                    RoleDisplayName = GetRoleDisplayName(roleName),
                    PermissionId = moduleRequest.PermissionId,
                    CanView = moduleRequest.CanView,
                    CanCreate = moduleRequest.CanCreate,
                    CanEdit = moduleRequest.CanEdit,
                    CanDelete = moduleRequest.CanDelete,
                    CanExport = moduleRequest.CanExport,
                    CanApprove = moduleRequest.CanApprove
                };
                context.RolePermissions.Add(newPermission);
            }
        }

        await context.SaveChangesAsync();

        return Ok(AppResponse<bool>.Success(true));
    }

    /// <summary>
    /// Reset permissions của một role về mặc định
    /// </summary>
    [HttpPost("reset/{roleName}")]
    [RequirePermission("Role", PermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<bool>>> ResetPermissions(string roleName)
    {
        if (roleName.Equals("Admin", StringComparison.OrdinalIgnoreCase))
        {
            return BadRequest(AppResponse<bool>.Error("Không thể reset quyền của Admin"));
        }

        // Xóa permissions hiện tại
        var existingPermissions = await context.RolePermissions
            .Where(p => p.StoreId == RequiredStoreId && p.RoleName == roleName)
            .ToListAsync();

        context.RolePermissions.RemoveRange(existingPermissions);

        // Tạo permissions mặc định
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
        GetDefaultPermissions(string roleName, string module)
    {
        return roleName.ToLower() switch
        {
            // Admin có full quyền
            "admin" => (true, true, true, true, true, true),
            
            // Giám đốc: gần như full, trừ cấu hình hệ thống
            "director" => module.ToLower() switch
            {
                "settings" or "device" or "geofence" or "deviceuser" => (true, false, false, false, false, false),
                "store" or "role" or "usermanagement" or "departmentpermission" => (true, false, false, false, true, false),
                _ => (true, true, true, true, true, true)
            },
            
            // Kế toán: tập trung tài chính, lương, bảo hiểm, thuế
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
            
            // Trưởng phòng: quản lý nhân sự phòng ban, duyệt đơn từ
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
            
            // Manager có hầu hết quyền, trừ một số module nhạy cảm
            "manager" => module.ToLower() switch
            {
                "settings" or "store" or "role" => (true, false, false, false, false, false),
                _ => (true, true, true, false, true, true)
            },
            
            // Employee chỉ xem và tạo đơn từ
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
            
            // User chỉ xem được thông tin cơ bản
            "user" => module.ToLower() switch
            {
                "dashboard" => (true, false, false, false, false, false),
                _ => (false, false, false, false, false, false)
            },
            
            _ => (false, false, false, false, false, false)
        };
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

    #endregion
}

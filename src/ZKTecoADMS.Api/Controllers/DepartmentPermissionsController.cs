using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Attributes;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.DTOs.Permissions;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
public class DepartmentPermissionsController(ZKTecoDbContext context, IDataScopeService dataScopeService) : AuthenticatedControllerBase
{
    /// <summary>
    /// Lấy cây phòng ban kèm thông tin quyền
    /// </summary>
    [HttpGet("department-tree")]
    [RequirePermission("DepartmentPermission", PermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<DepartmentTreeNodeDto>>>> GetDepartmentTree(
        [FromQuery] Guid? storeId = null)
    {
        var effectiveStoreId = storeId ?? CurrentStoreId;

        var departments = await context.Departments
            .Where(d => d.StoreId == effectiveStoreId && d.Deleted == null)
            .OrderBy(d => d.SortOrder)
            .ThenBy(d => d.Name)
            .Select(d => new
            {
                d.Id,
                d.Code,
                d.Name,
                d.ParentDepartmentId,
                d.Level,
                d.ManagerId,
                EmployeeCount = d.Employees.Count,
                PermissionCount = context.DepartmentPermissions
                    .Count(dp => dp.DepartmentId == d.Id && dp.IsActive)
            })
            .ToListAsync();

        // Lấy tên manager
        var managerIds = departments.Where(d => d.ManagerId.HasValue).Select(d => d.ManagerId!.Value).Distinct().ToList();
        var managers = await context.Employees
            .Where(e => managerIds.Contains(e.Id))
            .Select(e => new { e.Id, Name = e.LastName + " " + e.FirstName })
            .ToDictionaryAsync(e => e.Id, e => e.Name);

        var allNodes = departments.Select(d => new DepartmentTreeNodeDto
        {
            Id = d.Id,
            Code = d.Code,
            Name = d.Name,
            ParentDepartmentId = d.ParentDepartmentId,
            Level = d.Level,
            ManagerId = d.ManagerId,
            ManagerName = d.ManagerId.HasValue && managers.ContainsKey(d.ManagerId.Value)
                ? managers[d.ManagerId.Value] : null,
            EmployeeCount = d.EmployeeCount,
            PermissionCount = d.PermissionCount
        }).ToList();

        // Build tree
        var lookup = allNodes.ToLookup(n => n.ParentDepartmentId);
        foreach (var node in allNodes)
        {
            node.Children = lookup[node.Id].ToList();
        }
        var roots = allNodes.Where(n => n.ParentDepartmentId == null).ToList();

        return Ok(AppResponse<List<DepartmentTreeNodeDto>>.Success(roots));
    }

    /// <summary>
    /// Lấy quyền phòng ban theo user
    /// </summary>
    [HttpGet("by-user/{userId}")]
    [RequirePermission("DepartmentPermission", PermissionAction.View)]
    public async Task<ActionResult<AppResponse<UserDepartmentPermissionGroupDto>>> GetByUser(Guid userId,
        [FromQuery] Guid? storeId = null)
    {
        var effectiveStoreId = storeId ?? CurrentStoreId;

        var user = await context.Users
            .Where(u => u.Id == userId)
            .Select(u => new { u.Id, u.UserName, u.FullName })
            .FirstOrDefaultAsync();

        if (user == null)
            return NotFound(AppResponse<object>.Error("User không tồn tại"));

        var permissions = await context.DepartmentPermissions
            .Include(dp => dp.Permission)
            .Include(dp => dp.Department)
            .Where(dp => dp.UserId == userId &&
                         (dp.StoreId == effectiveStoreId || dp.StoreId == null) &&
                         dp.IsActive)
            .OrderBy(dp => dp.Department!.Name)
            .ThenBy(dp => dp.Permission!.DisplayOrder)
            .ToListAsync();

        var grouped = permissions
            .GroupBy(dp => new { dp.DepartmentId, DeptName = dp.Department?.Name, dp.IncludeChildren })
            .Select(g => new DepartmentPermissionItemDto
            {
                DepartmentId = g.Key.DepartmentId,
                DepartmentName = g.Key.DeptName ?? "Tất cả phòng ban",
                IncludeChildren = g.Key.IncludeChildren,
                Permissions = g.Select(dp => new ModulePermissionDto
                {
                    PermissionId = dp.PermissionId,
                    Module = dp.Permission!.Module,
                    ModuleDisplayName = dp.Permission.ModuleDisplayName,
                    DisplayOrder = dp.Permission.DisplayOrder,
                    CanView = dp.CanView,
                    CanCreate = dp.CanCreate,
                    CanEdit = dp.CanEdit,
                    CanDelete = dp.CanDelete,
                    CanExport = dp.CanExport,
                    CanApprove = dp.CanApprove
                }).ToList()
            }).ToList();

        var result = new UserDepartmentPermissionGroupDto
        {
            UserId = user.Id,
            UserName = user.UserName,
            FullName = user.FullName,
            DepartmentPermissions = grouped
        };

        return Ok(AppResponse<UserDepartmentPermissionGroupDto>.Success(result));
    }

    /// <summary>
    /// Lấy quyền phòng ban theo department
    /// </summary>
    [HttpGet("by-department/{departmentId}")]
    [RequirePermission("DepartmentPermission", PermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<DepartmentPermissionDto>>>> GetByDepartment(Guid departmentId,
        [FromQuery] Guid? storeId = null)
    {
        var effectiveStoreId = storeId ?? CurrentStoreId;

        var permissions = await context.DepartmentPermissions
            .Include(dp => dp.Permission)
            .Include(dp => dp.User)
            .Where(dp => dp.DepartmentId == departmentId &&
                         (dp.StoreId == effectiveStoreId || dp.StoreId == null) &&
                         dp.IsActive)
            .OrderBy(dp => dp.User!.FullName)
            .ThenBy(dp => dp.Permission!.DisplayOrder)
            .Select(dp => new DepartmentPermissionDto
            {
                Id = dp.Id,
                UserId = dp.UserId,
                UserName = dp.User!.UserName,
                FullName = dp.User.FullName,
                DepartmentId = dp.DepartmentId,
                DepartmentName = dp.Department!.Name,
                PermissionId = dp.PermissionId,
                Module = dp.Permission!.Module,
                ModuleDisplayName = dp.Permission.ModuleDisplayName,
                IncludeChildren = dp.IncludeChildren,
                StoreId = dp.StoreId,
                CanView = dp.CanView,
                CanCreate = dp.CanCreate,
                CanEdit = dp.CanEdit,
                CanDelete = dp.CanDelete,
                CanExport = dp.CanExport,
                CanApprove = dp.CanApprove,
                IsActive = dp.IsActive,
                GrantedBy = dp.GrantedBy,
                Note = dp.Note,
                CreatedAt = dp.CreatedAt
            })
            .ToListAsync();

        return Ok(AppResponse<List<DepartmentPermissionDto>>.Success(permissions));
    }

    /// <summary>
    /// Gán quyền phòng ban cho user
    /// </summary>
    [HttpPost]
    [RequirePermission("DepartmentPermission", PermissionAction.Create)]
    public async Task<ActionResult<AppResponse<object>>> AssignPermissions(
        [FromBody] CreateDepartmentPermissionRequest request)
    {
        var effectiveStoreId = request.StoreId ?? CurrentStoreId;

        // Xóa quyền cũ của user trong department + store
        var oldPermissions = await context.DepartmentPermissions
            .Where(dp => dp.UserId == request.UserId &&
                         dp.DepartmentId == request.DepartmentId &&
                         (dp.StoreId == effectiveStoreId || dp.StoreId == null))
            .ToListAsync();

        context.DepartmentPermissions.RemoveRange(oldPermissions);

        // Thêm quyền mới
        var currentUserName = User.Identity?.Name ?? "system";
        foreach (var perm in request.Permissions)
        {
            if (!perm.CanView && !perm.CanCreate && !perm.CanEdit &&
                !perm.CanDelete && !perm.CanExport && !perm.CanApprove)
                continue; // Bỏ qua nếu không có quyền nào

            context.DepartmentPermissions.Add(new DepartmentPermission
            {
                Id = Guid.NewGuid(),
                UserId = request.UserId,
                DepartmentId = request.DepartmentId,
                PermissionId = perm.PermissionId,
                IncludeChildren = request.IncludeChildren,
                StoreId = effectiveStoreId,
                CanView = perm.CanView,
                CanCreate = perm.CanCreate,
                CanEdit = perm.CanEdit,
                CanDelete = perm.CanDelete,
                CanExport = perm.CanExport,
                CanApprove = perm.CanApprove,
                IsActive = true,
                GrantedBy = currentUserName,
                Note = request.Note,
                CreatedAt = DateTime.UtcNow,
                CreatedBy = currentUserName
            });
        }

        await context.SaveChangesAsync();

        return Ok(AppResponse<object>.Success(null));
    }

    /// <summary>
    /// Xóa quyền phòng ban cho user trong một department
    /// </summary>
    [HttpDelete("{userId}/{departmentId}")]
    [RequirePermission("DepartmentPermission", PermissionAction.Delete)]
    public async Task<ActionResult<AppResponse<object>>> RevokePermissions(
        Guid userId, Guid departmentId, [FromQuery] Guid? storeId = null)
    {
        var effectiveStoreId = storeId ?? CurrentStoreId;

        var permissions = await context.DepartmentPermissions
            .Where(dp => dp.UserId == userId &&
                         dp.DepartmentId == departmentId &&
                         (dp.StoreId == effectiveStoreId || dp.StoreId == null))
            .ToListAsync();

        if (!permissions.Any())
            return NotFound(AppResponse<object>.Error("Không tìm thấy quyền phòng ban"));

        context.DepartmentPermissions.RemoveRange(permissions);
        await context.SaveChangesAsync();

        return Ok(AppResponse<object>.Success(null));
    }

    /// <summary>
    /// Lấy quyền phòng ban hiệu lực của current user (cho frontend check)
    /// </summary>
    [HttpGet("my-permissions")]
    public async Task<ActionResult<AppResponse<List<DepartmentPermissionDto>>>> GetMyDepartmentPermissions()
    {
        var userId = CurrentUserId;
        var storeId = CurrentStoreId;

        var permissions = await context.DepartmentPermissions
            .Include(dp => dp.Permission)
            .Include(dp => dp.Department)
            .Where(dp => dp.UserId == userId &&
                         (dp.StoreId == storeId || dp.StoreId == null) &&
                         dp.IsActive)
            .OrderBy(dp => dp.Permission!.DisplayOrder)
            .Select(dp => new DepartmentPermissionDto
            {
                Id = dp.Id,
                UserId = dp.UserId,
                DepartmentId = dp.DepartmentId,
                DepartmentName = dp.Department != null ? dp.Department.Name : "Tất cả",
                PermissionId = dp.PermissionId,
                Module = dp.Permission!.Module,
                ModuleDisplayName = dp.Permission.ModuleDisplayName,
                IncludeChildren = dp.IncludeChildren,
                StoreId = dp.StoreId,
                CanView = dp.CanView,
                CanCreate = dp.CanCreate,
                CanEdit = dp.CanEdit,
                CanDelete = dp.CanDelete,
                CanExport = dp.CanExport,
                CanApprove = dp.CanApprove,
                IsActive = dp.IsActive,
                CreatedAt = dp.CreatedAt
            })
            .ToListAsync();

        return Ok(AppResponse<List<DepartmentPermissionDto>>.Success(permissions));
    }

    /// <summary>
    /// Kiểm tra user có quyền cụ thể trong phòng ban không
    /// </summary>
    [HttpGet("check")]
    public async Task<ActionResult<AppResponse<bool>>> CheckDepartmentPermission(
        [FromQuery] string module, [FromQuery] string action, [FromQuery] Guid? departmentId = null)
    {
        var userId = CurrentUserId;
        var storeId = CurrentStoreId;

        var query = context.DepartmentPermissions
            .Include(dp => dp.Permission)
            .Include(dp => dp.Department)
            .Where(dp => dp.UserId == userId &&
                         dp.Permission!.Module == module &&
                         (dp.StoreId == storeId || dp.StoreId == null) &&
                         dp.IsActive);

        if (departmentId.HasValue)
        {
            // Kiểm tra quyền trực tiếp hoặc quyền kế thừa từ phòng ban cha
            var dept = await context.Departments
                .Where(d => d.Id == departmentId.Value)
                .Select(d => new { d.Id, d.HierarchyPath })
                .FirstOrDefaultAsync();

            if (dept == null)
                return Ok(AppResponse<bool>.Success(false));

            query = query.Where(dp =>
                dp.DepartmentId == null || // Quyền tất cả phòng ban
                dp.DepartmentId == departmentId.Value || // Quyền trực tiếp
                (dp.IncludeChildren && dept.HierarchyPath != null &&
                 dept.HierarchyPath.Contains(dp.DepartmentId.ToString()!))); // Kế thừa từ cha
        }

        var permission = await query.FirstOrDefaultAsync();
        if (permission == null)
            return Ok(AppResponse<bool>.Success(false));

        var hasPermission = action.ToLower() switch
        {
            "view" => permission.CanView,
            "create" => permission.CanCreate,
            "edit" => permission.CanEdit,
            "delete" => permission.CanDelete,
            "export" => permission.CanExport,
            "approve" => permission.CanApprove,
            _ => false
        };

        return Ok(AppResponse<bool>.Success(hasPermission));
    }

    /// <summary>
    /// Lấy phạm vi quản lý của current user (danh sách PB được quản lý + số NV)
    /// </summary>
    [HttpGet("my-scope")]
    public async Task<ActionResult<AppResponse<object>>> GetMyScope()
    {
        var storeId = CurrentStoreId;
        if (!storeId.HasValue)
            return Ok(AppResponse<object>.Success(new { departments = new List<object>(), employeeCount = 0 }));

        // Admin xem tất cả
        if (IsAdmin)
        {
            var allDepts = await context.Departments
                .Where(d => d.StoreId == storeId.Value && d.Deleted == null)
                .Select(d => new { d.Id, d.Code, d.Name, d.Level })
                .ToListAsync();
            var allEmpIds = await context.Employees
                .Where(e => e.StoreId == storeId.Value)
                .Select(e => e.Id)
                .ToListAsync();
            return Ok(AppResponse<object>.Success(new
            {
                departments = allDepts,
                employeeCount = allEmpIds.Count,
                subordinateEmployeeIds = allEmpIds
            }));
        }

        var managedDeptIds = await dataScopeService.GetManagedDepartmentIdsAsync(CurrentUserId, storeId.Value);
        var subordinateEmployeeIds = await dataScopeService.GetSubordinateEmployeeIdsAsync(CurrentUserId, storeId.Value);

        var departments = await context.Departments
            .Where(d => managedDeptIds.Contains(d.Id))
            .Select(d => new { d.Id, d.Code, d.Name, d.Level })
            .ToListAsync();

        return Ok(AppResponse<object>.Success(new
        {
            departments,
            employeeCount = subordinateEmployeeIds.Count,
            subordinateEmployeeIds
        }));
    }
}

using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Attributes;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.DTOs.Commons;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// Controller Ä‘á»ƒ quáº£n lÃ½ ngÆ°á»i dÃ¹ng trong cá»­a hÃ ng
/// </summary>
[ApiController]
[Route("api/users")]
[Authorize]
public class UserManagementController(
    UserManager<ApplicationUser> userManager,
    RoleManager<IdentityRole<Guid>> roleManager,
    ZKTecoDbContext context
) : AuthenticatedControllerBase
{
    #region List Users
    
    /// <summary>
    /// Láº¥y danh sÃ¡ch táº¥t cáº£ users trong cá»­a hÃ ng (cÃ³ phÃ¢n trang)
    /// </summary>
    [HttpGet]
    [Authorize(Policy = PolicyNames.AtLeastAdmin)]
    [RequirePermission("Account", PermissionAction.View)]
    [RequireModulePermission("UserManagement", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<PagedResult<UserDto>>>> GetUsers(
        [FromQuery] int pageNumber = 1,
        [FromQuery] int pageSize = 20,
        [FromQuery] string? search = null,
        [FromQuery] string? role = null,
        [FromQuery] bool? isLocked = null)
    {
        var query = userManager.Users
            .Where(u => u.StoreId == RequiredStoreId)
            .Include(u => u.Employee)
            .AsQueryable();

        // Filter by search term
        if (!string.IsNullOrEmpty(search))
        {
            var searchPattern = $"%{search}%";
            query = query.Where(u => 
                (u.Email != null && EF.Functions.ILike(u.Email, searchPattern)) ||
                (u.FirstName != null && EF.Functions.ILike(u.FirstName, searchPattern)) ||
                (u.LastName != null && EF.Functions.ILike(u.LastName, searchPattern)) ||
                (u.UserName != null && EF.Functions.ILike(u.UserName, searchPattern)));
        }

        // Filter by locked status
        if (isLocked.HasValue)
        {
            if (isLocked.Value)
            {
                query = query.Where(u => u.LockoutEnd != null && u.LockoutEnd > DateTimeOffset.UtcNow);
            }
            else
            {
                query = query.Where(u => u.LockoutEnd == null || u.LockoutEnd <= DateTimeOffset.UtcNow);
            }
        }

        var totalCount = await query.CountAsync();
        
        var users = await query
            .OrderByDescending(u => u.CreatedAt)
            .Skip((pageNumber - 1) * pageSize)
            .Take(pageSize)
            .ToListAsync();

        // Pre-load user-role mappings to avoid N+1
        var userIds = users.Select(u => u.Id).ToList();
        var userRoles = await context.UserRoles
            .Where(ur => userIds.Contains(ur.UserId))
            .Join(context.Roles, ur => ur.RoleId, r => r.Id, (ur, r) => new { ur.UserId, r.Name })
            .GroupBy(x => x.UserId)
            .ToDictionaryAsync(g => g.Key, g => g.Select(x => x.Name!).ToList());

        var userDtos = new List<UserDto>();
        foreach (var user in users)
        {
            var roles = userRoles.GetValueOrDefault(user.Id) ?? new List<string>();
            
            // Filter by role if specified
            if (!string.IsNullOrEmpty(role) && !roles.Contains(role))
            {
                continue;
            }
            
            userDtos.Add(new UserDto
            {
                Id = user.Id,
                Email = user.Email ?? "",
                UserName = user.UserName ?? "",
                FirstName = user.FirstName ?? "",
                LastName = user.LastName ?? "",
                PhoneNumber = user.PhoneNumber,
                Roles = roles.ToList(),
                IsLocked = user.LockoutEnd != null && user.LockoutEnd > DateTimeOffset.UtcNow,
                LockoutEnd = user.LockoutEnd,
                EmployeeId = user.Employee?.Id,
                EmployeeCode = user.Employee?.EmployeeCode,
                CreatedAt = user.CreatedAt,
                EmailConfirmed = user.EmailConfirmed
            });
        }

        var result = new PagedResult<UserDto>(userDtos, totalCount, pageNumber, pageSize);
        return Ok(AppResponse<PagedResult<UserDto>>.Success(result));
    }

    /// <summary>
    /// Láº¥y thÃ´ng tin chi tiáº¿t user theo ID
    /// </summary>
    [HttpGet("{userId}")]
    [Authorize(Policy = PolicyNames.AtLeastAdmin)]
    [RequirePermission("Account", PermissionAction.View)]
    [RequireModulePermission("UserManagement", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<UserDto>>> GetUserById(Guid userId)
    {
        var user = await userManager.Users
            .Include(u => u.Employee)
            .Include(u => u.Manager)
            .FirstOrDefaultAsync(u => u.Id == userId && u.StoreId == RequiredStoreId);

        if (user == null)
        {
            return NotFound(AppResponse<UserDto>.Error("User not found"));
        }

        var roles = await userManager.GetRolesAsync(user);

        return Ok(AppResponse<UserDto>.Success(new UserDto
        {
            Id = user.Id,
            Email = user.Email ?? "",
            UserName = user.UserName ?? "",
            FirstName = user.FirstName ?? "",
            LastName = user.LastName ?? "",
            PhoneNumber = user.PhoneNumber,
            Roles = roles.ToList(),
            IsLocked = user.LockoutEnd != null && user.LockoutEnd > DateTimeOffset.UtcNow,
            LockoutEnd = user.LockoutEnd,
            EmployeeId = user.Employee?.Id,
            EmployeeCode = user.Employee?.EmployeeCode,
            ManagerId = user.ManagerId,
            ManagerName = user.Manager?.GetFullName(),
            CreatedAt = user.CreatedAt,
            EmailConfirmed = user.EmailConfirmed
        }));
    }

    #endregion

    #region Change Role

    /// <summary>
    /// Thay Ä‘á»•i role cá»§a user
    /// </summary>
    [HttpPut("{userId}/role")]
    [Authorize(Policy = PolicyNames.AtLeastAdmin)]
    [RequirePermission("Role", PermissionAction.Edit)]
    [RequireModulePermission("UserManagement", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<bool>>> ChangeUserRole(Guid userId, [FromBody] ChangeRoleRequest request)
    {
        var user = await userManager.Users
            .FirstOrDefaultAsync(u => u.Id == userId && u.StoreId == RequiredStoreId);

        if (user == null)
        {
            return NotFound(AppResponse<bool>.Error("User not found"));
        }

        // KhÃ´ng cho phÃ©p tá»± Ä‘á»•i role cá»§a chÃ­nh mÃ¬nh
        if (userId == CurrentUserId)
        {
            return BadRequest(AppResponse<bool>.Error("KhÃ´ng thá»ƒ thay Ä‘á»•i role cá»§a chÃ­nh mÃ¬nh"));
        }

        // Kiá»ƒm tra role cÃ³ tá»“n táº¡i khÃ´ng
        if (!await roleManager.RoleExistsAsync(request.NewRole))
        {
            return BadRequest(AppResponse<bool>.Error($"Role '{request.NewRole}' khÃ´ng tá»“n táº¡i"));
        }

        // XÃ³a táº¥t cáº£ role hiá»‡n táº¡i
        var currentRoles = await userManager.GetRolesAsync(user);
        await userManager.RemoveFromRolesAsync(user, currentRoles);

        // ThÃªm role má»›i
        var result = await userManager.AddToRoleAsync(user, request.NewRole);
        if (!result.Succeeded)
        {
            return BadRequest(AppResponse<bool>.Error(result.Errors.Select(e => e.Description)));
        }

        // Äá»“ng bá»™ cá»™t Role Ä‘á»ƒ UI vÃ  dá»¯ liá»‡u hiá»ƒn thá»‹ luÃ´n khá»›p vá»›i Identity role
        user.Role = request.NewRole;
        var updateResult = await userManager.UpdateAsync(user);
        if (!updateResult.Succeeded)
        {
            return BadRequest(AppResponse<bool>.Error(updateResult.Errors.Select(e => e.Description)));
        }

        return Ok(AppResponse<bool>.Success(true));
    }

    /// <summary>
    /// Láº¥y danh sÃ¡ch roles cÃ³ sáºµn
    /// </summary>
    [HttpGet("available-roles")]
    [Authorize(Policy = PolicyNames.AtLeastAdmin)]
    [RequireModulePermission("UserManagement", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<string>>>> GetAvailableRoles()
    {
        var roles = await roleManager.Roles.Select(r => r.Name!).ToListAsync();
        return Ok(AppResponse<List<string>>.Success(roles));
    }

    #endregion

    #region Lock/Unlock User

    /// <summary>
    /// KhÃ³a tÃ i khoáº£n user
    /// </summary>
    [HttpPost("{userId}/lock")]
    [Authorize(Policy = PolicyNames.AtLeastAdmin)]
    [RequirePermission("Account", PermissionAction.Edit)]
    [RequireModulePermission("UserManagement", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<bool>>> LockUser(Guid userId, [FromBody] LockUserRequest request)
    {
        var user = await userManager.Users
            .FirstOrDefaultAsync(u => u.Id == userId && u.StoreId == RequiredStoreId);

        if (user == null)
        {
            return NotFound(AppResponse<bool>.Error("User not found"));
        }

        // KhÃ´ng cho phÃ©p tá»± khÃ³a chÃ­nh mÃ¬nh
        if (userId == CurrentUserId)
        {
            return BadRequest(AppResponse<bool>.Error("KhÃ´ng thá»ƒ khÃ³a tÃ i khoáº£n cá»§a chÃ­nh mÃ¬nh"));
        }

        // Thiáº¿t láº­p thá»i gian khÃ³a
        var lockoutEnd = request.LockoutDays.HasValue 
            ? DateTimeOffset.UtcNow.AddDays(request.LockoutDays.Value)
            : DateTimeOffset.UtcNow.AddYears(100); // KhÃ³a vÄ©nh viá»…n

        await userManager.SetLockoutEndDateAsync(user, lockoutEnd);
        await userManager.SetLockoutEnabledAsync(user, true);

        return Ok(AppResponse<bool>.Success(true));
    }

    /// <summary>
    /// Má»Ÿ khÃ³a tÃ i khoáº£n user
    /// </summary>
    [HttpPost("{userId}/unlock")]
    [Authorize(Policy = PolicyNames.AtLeastAdmin)]
    [RequirePermission("Account", PermissionAction.Edit)]
    [RequireModulePermission("UserManagement", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<bool>>> UnlockUser(Guid userId)
    {
        var user = await userManager.Users
            .FirstOrDefaultAsync(u => u.Id == userId && u.StoreId == RequiredStoreId);

        if (user == null)
        {
            return NotFound(AppResponse<bool>.Error("User not found"));
        }

        await userManager.SetLockoutEndDateAsync(user, null);
        await userManager.ResetAccessFailedCountAsync(user);

        return Ok(AppResponse<bool>.Success(true));
    }

    #endregion

    #region Reset Password

    /// <summary>
    /// Admin reset máº­t kháº©u cho user
    /// </summary>
    [HttpPost("{userId}/reset-password")]
    [Authorize(Policy = PolicyNames.AtLeastAdmin)]
    [RequirePermission("Account", PermissionAction.Edit)]
    [RequireModulePermission("UserManagement", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<string>>> ResetPassword(Guid userId, [FromBody] ResetPasswordRequest request)
    {
        var user = await userManager.Users
            .FirstOrDefaultAsync(u => u.Id == userId && u.StoreId == RequiredStoreId);

        if (user == null)
        {
            return NotFound(AppResponse<string>.Error("User not found"));
        }

        // Generate password reset token
        var token = await userManager.GeneratePasswordResetTokenAsync(user);
        
        // Reset password
        var result = await userManager.ResetPasswordAsync(user, token, request.NewPassword);
        if (!result.Succeeded)
        {
            return BadRequest(AppResponse<string>.Error(result.Errors.Select(e => e.Description)));
        }

        return Ok(AppResponse<string>.Success("ÄÃ£ reset máº­t kháº©u thÃ nh cÃ´ng"));
    }

    #endregion

    #region Update User

    /// <summary>
    /// Cáº­p nháº­t thÃ´ng tin user
    /// </summary>
    [HttpPut("{userId}")]
    [Authorize(Policy = PolicyNames.AtLeastAdmin)]
    [RequirePermission("Account", PermissionAction.Edit)]
    [RequireModulePermission("UserManagement", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<UserDto>>> UpdateUser(Guid userId, [FromBody] UpdateUserRequest request)
    {
        var user = await userManager.Users
            .Include(u => u.Employee)
            .FirstOrDefaultAsync(u => u.Id == userId && u.StoreId == RequiredStoreId);

        if (user == null)
        {
            return NotFound(AppResponse<UserDto>.Error("User not found"));
        }

        // Update fields
        if (!string.IsNullOrEmpty(request.FirstName))
            user.FirstName = request.FirstName;
        
        if (!string.IsNullOrEmpty(request.LastName))
            user.LastName = request.LastName;
        
        if (!string.IsNullOrEmpty(request.PhoneNumber))
            user.PhoneNumber = request.PhoneNumber;

        if (request.ManagerId.HasValue)
        {
            // Validate manager exists and belongs to same store
            var manager = await userManager.Users
                .FirstOrDefaultAsync(u => u.Id == request.ManagerId && u.StoreId == RequiredStoreId);
            
            if (manager != null)
            {
                user.ManagerId = request.ManagerId;
            }
        }

        var result = await userManager.UpdateAsync(user);
        if (!result.Succeeded)
        {
            return BadRequest(AppResponse<UserDto>.Error(result.Errors.Select(e => e.Description)));
        }

        var roles = await userManager.GetRolesAsync(user);

        return Ok(AppResponse<UserDto>.Success(new UserDto
        {
            Id = user.Id,
            Email = user.Email ?? "",
            UserName = user.UserName ?? "",
            FirstName = user.FirstName ?? "",
            LastName = user.LastName ?? "",
            PhoneNumber = user.PhoneNumber,
            Roles = roles.ToList(),
            ManagerId = user.ManagerId,
            EmployeeId = user.Employee?.Id,
            CreatedAt = user.CreatedAt
        }));
    }

    #endregion

    #region Delete User

    /// <summary>
    /// XÃ³a user (soft delete - chá»‰ deactivate)
    /// </summary>
    [HttpDelete("{userId}")]
    [Authorize(Policy = PolicyNames.AtLeastAdmin)]
    [RequirePermission("Account", PermissionAction.Delete)]
    [RequireModulePermission("UserManagement", ModulePermissionAction.Delete)]
    public async Task<ActionResult<AppResponse<bool>>> DeleteUser(Guid userId)
    {
        var user = await userManager.Users
            .FirstOrDefaultAsync(u => u.Id == userId && u.StoreId == RequiredStoreId);

        if (user == null)
        {
            return NotFound(AppResponse<bool>.Error("User not found"));
        }

        // KhÃ´ng cho phÃ©p xÃ³a chÃ­nh mÃ¬nh
        if (userId == CurrentUserId)
        {
            return BadRequest(AppResponse<bool>.Error("KhÃ´ng thá»ƒ xÃ³a tÃ i khoáº£n cá»§a chÃ­nh mÃ¬nh"));
        }

        // Kiá»ƒm tra user cÃ³ pháº£i owner cá»§a store khÃ´ng
        var isOwner = await context.Stores.AnyAsync(s => s.OwnerId == userId);
        if (isOwner)
        {
            return BadRequest(AppResponse<bool>.Error("KhÃ´ng thá»ƒ xÃ³a tÃ i khoáº£n owner cá»§a cá»­a hÃ ng"));
        }

        // Hard delete user
        var result = await userManager.DeleteAsync(user);
        if (!result.Succeeded)
        {
            return BadRequest(AppResponse<bool>.Error(result.Errors.Select(e => e.Description)));
        }

        return Ok(AppResponse<bool>.Success(true));
    }

    #endregion
}

#region Request/Response DTOs

public class UserDto
{
    public Guid Id { get; set; }
    public string Email { get; set; } = string.Empty;
    public string UserName { get; set; } = string.Empty;
    public string FirstName { get; set; } = string.Empty;
    public string LastName { get; set; } = string.Empty;
    public string? PhoneNumber { get; set; }
    public List<string> Roles { get; set; } = [];
    public bool IsLocked { get; set; }
    public DateTimeOffset? LockoutEnd { get; set; }
    public Guid? EmployeeId { get; set; }
    public string? EmployeeCode { get; set; }
    public Guid? ManagerId { get; set; }
    public string? ManagerName { get; set; }
    public DateTime CreatedAt { get; set; }
    public bool EmailConfirmed { get; set; }
}

public class ChangeRoleRequest
{
    public string NewRole { get; set; } = string.Empty;
}

public class LockUserRequest
{
    /// <summary>
    /// Sá»‘ ngÃ y khÃ³a. Null = khÃ³a vÄ©nh viá»…n
    /// </summary>
    public int? LockoutDays { get; set; }
}

public class ResetPasswordRequest
{
    public string NewPassword { get; set; } = string.Empty;
}

public class UpdateUserRequest
{
    public string? FirstName { get; set; }
    public string? LastName { get; set; }
    public string? PhoneNumber { get; set; }
    public Guid? ManagerId { get; set; }
}

#endregion


using Mapster;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Commands.Accounts.UpdateEmployeeAccount;
using ZKTecoADMS.Application.Commands.Accounts.UpdateUserProfile;
using ZKTecoADMS.Application.Commands.Accounts.UpdateUserPassword;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Application.Queries.DeviceUsers.GetDeviceUsersByManager;
using ZKTecoADMS.Application.Queries.Users.GetCurrentUserProfile;
using ZKTecoADMS.Application.Queries.Users.GetStoreAccounts;
using ZKTecoADMS.Application.DTOs.Commons;
using ZKTecoADMS.Application.Commands.Accounts;
using ZKTecoADMS.Application.Commands.Accounts.BulkCreateEmployeeAccounts;
using ZKTecoADMS.Application.DTOs.Employees;
using ZKTecoADMS.Application.DTOs.Accounts;
using ZKTecoADMS.Application.DTOs.Permissions;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.DTOs.SystemAdmin;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Helpers;

namespace ZKTecoADMS.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
public class AccountsController(IMediator mediator, UserManager<ApplicationUser> userManager, IDataScopeService dataScopeService, ZKTecoDbContext dbContext) : AuthenticatedControllerBase
{
    [HttpGet]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<IEnumerable<AccountDto>>>> GetStoreAccounts(CancellationToken cancellationToken)
    {
        var query = new GetStoreAccountsQuery(RequiredStoreId);
        var result = await mediator.Send(query, cancellationToken);
        return Ok(result);
    }

    [HttpGet("DeviceUsers")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<IEnumerable<AccountDto>>>> GetDeviceUsersByManager(CancellationToken cancellationToken)
    {
        List<Guid>? subordinateUserIds = null;
        if (!IsAdmin)
            subordinateUserIds = await dataScopeService.GetSubordinateUserIdsAsync(CurrentUserId, RequiredStoreId);
        var query = new GetDeviceUsersByManagerQuery(CurrentUserId, subordinateUserIds);
        var result = await mediator.Send(query, cancellationToken);
        return Ok(result);
    }
    
    [HttpPost]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<AppResponse<AccountDto>> CreateEmployeeAccount([FromBody] CreateEmployeeAccountRequest request, CancellationToken cancellationToken)
    {
        var command = request.Adapt<CreateEmployeeAccountCommand>();
        command.ManagerId = CurrentUserId;
        
        return await mediator.Send(command, cancellationToken);
    }

    [HttpPost("bulk")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<AppResponse<BulkCreateEmployeeAccountsResult>> BulkCreateEmployeeAccounts(
        [FromBody] BulkCreateEmployeeAccountsRequest request,
        CancellationToken cancellationToken)
    {
        var command = new BulkCreateEmployeeAccountsCommand
        {
            EmployeeIds = request.EmployeeIds,
            Password = request.Password,
            Role = request.Role,
            ManagerId = CurrentUserId
        };
        return await mediator.Send(command, cancellationToken);
    }

    [HttpPut("{userId}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<AppResponse<bool>> UpdateEmployeeAccount(Guid userId, [FromBody] UpdateEmployeeAccountRequest request, CancellationToken cancellationToken)
    {
        var command = request.Adapt<UpdateEmployeeAccountCommand>();
        command.UserId = userId;
        command.StoreId = RequiredStoreId;
        var result = await mediator.Send(command, cancellationToken);

        return result;
    }

    [HttpGet("profile")]
    public async Task<ActionResult<AppResponse<AccountDto>>> GetProfile(CancellationToken cancellationToken)
    {
        var query = new GetCurrentUserProfileQuery(CurrentUserId);
        var result = await mediator.Send(query, cancellationToken);
        return Ok(result);
    }

    /// <summary>
    /// Liên hệ đại lý hỗ trợ cửa hàng hiện tại (Zalo / SĐT).
    /// </summary>
    [HttpGet("store-agent-contact")]
    public async Task<ActionResult<AppResponse<StoreAgentContactDto?>>> GetStoreAgentContact(CancellationToken cancellationToken)
    {
        var store = await dbContext.Stores
            .AsNoTracking()
            .Include(s => s.Agent)
            .FirstOrDefaultAsync(s => s.Id == RequiredStoreId, cancellationToken);

        if (store?.Agent == null || !store.Agent.IsActive)
        {
            return Ok(AppResponse<StoreAgentContactDto?>.Success(null));
        }

        var agent = store.Agent;
        var zaloUrl = BuildAgentZaloUrl(agent.Phone);
        var dto = new StoreAgentContactDto(
            agent.Id,
            agent.Name,
            agent.Code,
            agent.Phone,
            agent.Email,
            agent.Address,
            zaloUrl
        );
        return Ok(AppResponse<StoreAgentContactDto?>.Success(dto));
    }

    private static string? BuildAgentZaloUrl(string? phone)
    {
        if (string.IsNullOrWhiteSpace(phone)) return null;
        var digits = new string(phone.Where(char.IsDigit).ToArray());
        if (digits.StartsWith("84") && digits.Length > 10)
            digits = digits[2..];
        if (digits.StartsWith('0') && digits.Length > 9)
            digits = digits[1..];
        return string.IsNullOrEmpty(digits) ? null : $"https://zalo.me/{digits}";
    }

    [HttpPut("profile")]
    public async Task<ActionResult<AppResponse<AccountDto>>> UpdateProfile([FromBody] UpdateProfileRequest request, CancellationToken cancellationToken)
    {
        var command = new UpdateUserProfileCommand
        {
            UserId = CurrentUserId,
            FirstName = request.FirstName,
            LastName = request.LastName,
            PhoneNumber = request.PhoneNumber
        };
        var result = await mediator.Send(command, cancellationToken);
        return Ok(result);
    }

    [HttpPut("profile/password")]
    public async Task<ActionResult<AppResponse<AccountDto>>> UpdatePassword([FromBody] UpdatePasswordRequest request, CancellationToken cancellationToken)
    {
        var command = new UpdateUserPasswordCommand
        {
            UserId = CurrentUserId,
            CurrentPassword = request.CurrentPassword,
            NewPassword = request.NewPassword
        };
        var result = await mediator.Send(command, cancellationToken);
        return Ok(result);
    }

    [HttpDelete("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<bool>>> DeleteAccount(Guid id, CancellationToken cancellationToken)
    {
        var user = await userManager.FindByIdAsync(id.ToString());
        if (user == null || user.StoreId != RequiredStoreId)
        {
            return Ok(AppResponse<bool>.Error("Không tìm thấy tài khoản"));
        }

        // Don't allow deleting yourself or store owner
        if (user.Id == CurrentUserId)
        {
            return Ok(AppResponse<bool>.Error("Không thể xóa tài khoản của chính mình"));
        }

        var isOwner = await dbContext.Stores.AnyAsync(
            s => s.Id == RequiredStoreId && s.OwnerId == id,
            cancellationToken);
        if (isOwner)
        {
            return Ok(AppResponse<bool>.Error("Không thể xóa tài khoản chủ cửa hàng"));
        }

        try
        {
            // Gỡ / chuyển mọi FK trỏ tới user (giữ lịch sử nghiệp vụ: NULL hoặc gán cho người xóa).
            await UserAccountDeleteHelper.DetachReferencesAsync(
                dbContext,
                user.Id,
                CurrentUserId,
                cancellationToken);

            await dbContext.SaveChangesAsync(cancellationToken);

            var result = await userManager.DeleteAsync(user);
            if (!result.Succeeded)
            {
                return Ok(AppResponse<bool>.Error(result.Errors.Select(e => e.Description).ToList()));
            }
        }
        catch (DbUpdateException ex)
        {
            var detail = ex.InnerException?.Message ?? ex.Message;
            return Ok(AppResponse<bool>.Error(
                "Không thể xóa tài khoản vì còn dữ liệu liên quan. "
                + "Hãy dùng Vô hiệu hóa để giải phóng slot gói, hoặc thử lại sau. "
                + $"({detail})"));
        }

        return Ok(AppResponse<bool>.Success(true));
    }

    /// <summary>
    /// Activate / deactivate a store login account.
    /// Deactivate sets IsActive=false + Identity lockout and frees a package seat.
    /// </summary>
    [HttpPatch("{id}/status")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<bool>>> SetAccountStatus(
        Guid id,
        [FromBody] SetAccountStatusRequest request,
        CancellationToken cancellationToken,
        [FromServices] IStoreLicenseLimitService storeLicenseLimitService)
    {
        var user = await userManager.FindByIdAsync(id.ToString());
        if (user == null || user.StoreId != RequiredStoreId)
        {
            return Ok(AppResponse<bool>.Error("Không tìm thấy tài khoản"));
        }

        if (user.Id == CurrentUserId)
        {
            return Ok(AppResponse<bool>.Error("Không thể thay đổi trạng thái tài khoản của chính mình"));
        }

        var isOwner = await dbContext.Stores.AnyAsync(
            s => s.Id == RequiredStoreId && s.OwnerId == id,
            cancellationToken);
        if (isOwner)
        {
            return Ok(AppResponse<bool>.Error("Không thể vô hiệu hóa tài khoản chủ cửa hàng"));
        }

        if (request.IsActive == user.IsActive)
        {
            return Ok(AppResponse<bool>.Success(true));
        }

        if (request.IsActive)
        {
            var limitCheck = await storeLicenseLimitService.CanAddUserAsync(RequiredStoreId, cancellationToken);
            if (!limitCheck.Ok)
            {
                return Ok(AppResponse<bool>.Error(
                    limitCheck.Error ?? "Cửa hàng đã đạt giới hạn tài khoản theo gói dịch vụ."));
            }

            user.IsActive = true;
            await userManager.SetLockoutEndDateAsync(user, null);
            await userManager.ResetAccessFailedCountAsync(user);
            var updateResult = await userManager.UpdateAsync(user);
            if (!updateResult.Succeeded)
            {
                return Ok(AppResponse<bool>.Error(updateResult.Errors.Select(e => e.Description).ToList()));
            }

            return Ok(AppResponse<bool>.Success(true));
        }

        // Deactivate: free seat + block login/refresh/JWT
        user.IsActive = false;
        await userManager.SetLockoutEnabledAsync(user, true);
        await userManager.SetLockoutEndDateAsync(user, DateTimeOffset.UtcNow.AddYears(100));
        var deactivateResult = await userManager.UpdateAsync(user);
        if (!deactivateResult.Succeeded)
        {
            return Ok(AppResponse<bool>.Error(deactivateResult.Errors.Select(e => e.Description).ToList()));
        }

        var refreshTokens = await dbContext.UserRefreshTokens
            .Where(rt => rt.ApplicationUserId == id)
            .ToListAsync(cancellationToken);
        if (refreshTokens.Count > 0)
        {
            dbContext.RemoveRange(refreshTokens);
            await dbContext.SaveChangesAsync(cancellationToken);
        }

        return Ok(AppResponse<bool>.Success(true));
    }

    [HttpPatch("{id}/password")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<bool>>> ResetUserPassword(Guid id, [FromBody] ResetUserPasswordRequest request, CancellationToken cancellationToken)
    {
        var user = await userManager.FindByIdAsync(id.ToString());
        if (user == null || user.StoreId != RequiredStoreId)
        {
            return Ok(AppResponse<bool>.Error("Không tìm thấy tài khoản"));
        }

        var token = await userManager.GeneratePasswordResetTokenAsync(user);
        var result = await userManager.ResetPasswordAsync(user, token, request.Password);
        if (!result.Succeeded)
        {
            return Ok(AppResponse<bool>.Error(result.Errors.Select(e => e.Description).ToList()));
        }

        return Ok(AppResponse<bool>.Success(true));
    }

    private const string DataScopeModule = "DataScope";
    private static readonly Guid DataScopePermissionId =
        Guid.Parse("11111111-1111-1111-1111-111111111130");

    /// <summary>
    /// Phạm vi chi nhánh / phòng ban tài khoản được xem dữ liệu.
    /// </summary>
    [HttpGet("{userId}/data-scope")]
    [Authorize(Policy = PolicyNames.AtLeastAdmin)]
    [RequireModulePermission("Role", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<UserDataScopeDto>>> GetUserDataScope(Guid userId)
    {
        var storeId = RequiredStoreId;
        var user = await dbContext.Users.AsNoTracking()
            .FirstOrDefaultAsync(u => u.Id == userId && u.StoreId == storeId);
        if (user == null)
            return NotFound(AppResponse<UserDataScopeDto>.Error("Không tìm thấy tài khoản"));

        var role = user.Role ?? "";
        var isAdmin = role.Equals(nameof(Roles.Admin), StringComparison.OrdinalIgnoreCase)
                      || role.Equals(nameof(Roles.Director), StringComparison.OrdinalIgnoreCase)
                      || role.Equals(nameof(Roles.SuperAdmin), StringComparison.OrdinalIgnoreCase);

        var employeeId = await dbContext.Employees.AsNoTracking()
            .Where(e => e.ApplicationUserId == userId && e.StoreId == storeId)
            .Select(e => e.Id)
            .FirstOrDefaultAsync();

        var inheritedBranches = employeeId == Guid.Empty
            ? new List<Guid>()
            : await dbContext.Branches.AsNoTracking()
                .Where(b => b.ManagerId == employeeId && b.StoreId == storeId && b.Deleted == null)
                .Select(b => b.Id)
                .ToListAsync();

        var inheritedDepts = employeeId == Guid.Empty
            ? new List<Guid>()
            : await dbContext.Departments.AsNoTracking()
                .Where(d => d.ManagerId == employeeId && d.StoreId == storeId && d.Deleted == null)
                .Select(d => d.Id)
                .ToListAsync();

        var branchPerms = await dbContext.BranchPermissions.AsNoTracking()
            .Where(bp => bp.UserId == userId &&
                         (bp.StoreId == storeId || bp.StoreId == null) &&
                         bp.IsActive && bp.CanView)
            .Select(bp => new { bp.BranchId, bp.IncludeChildren })
            .ToListAsync();

        var dataScopePermId = await dbContext.Permissions.AsNoTracking()
            .Where(p => p.Module == DataScopeModule)
            .Select(p => (Guid?)p.Id)
            .FirstOrDefaultAsync();

        var allDepartments = false;
        var includeChildDepartments = true;
        var departmentIds = new List<Guid>();
        if (dataScopePermId != null)
        {
            var deptPerms = await dbContext.DepartmentPermissions.AsNoTracking()
                .Where(dp => dp.UserId == userId &&
                             dp.PermissionId == dataScopePermId &&
                             (dp.StoreId == storeId || dp.StoreId == null) &&
                             dp.IsActive && dp.CanView)
                .Select(dp => new { dp.DepartmentId, dp.IncludeChildren })
                .ToListAsync();
            allDepartments = deptPerms.Any(p => p.DepartmentId == null);
            includeChildDepartments = deptPerms.Count == 0 || deptPerms.Any(p => p.IncludeChildren);
            departmentIds = deptPerms.Where(p => p.DepartmentId.HasValue)
                .Select(p => p.DepartmentId!.Value).Distinct().ToList();
        }

        var dto = new UserDataScopeDto
        {
            UserId = user.Id,
            UserName = user.UserName,
            FullName = user.FullName,
            Role = role,
            IsAdmin = isAdmin,
            AllBranches = branchPerms.Any(p => p.BranchId == null),
            IncludeChildBranches = !branchPerms.Any() || branchPerms.Any(p => p.IncludeChildren),
            BranchIds = branchPerms.Where(p => p.BranchId.HasValue).Select(p => p.BranchId!.Value).Distinct().ToList(),
            InheritedBranchIds = inheritedBranches,
            AllDepartments = allDepartments,
            IncludeChildDepartments = includeChildDepartments,
            DepartmentIds = departmentIds,
            InheritedDepartmentIds = inheritedDepts,
        };

        return Ok(AppResponse<UserDataScopeDto>.Success(dto));
    }

    /// <summary>
    /// Gán chi nhánh / phòng ban tài khoản được xem dữ liệu (cộng với quyền trưởng CN/PB).
    /// </summary>
    [HttpPut("{userId}/data-scope")]
    [Authorize(Policy = PolicyNames.AtLeastAdmin)]
    [RequireModulePermission("Role", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<bool>>> UpdateUserDataScope(
        Guid userId, [FromBody] UpdateUserDataScopeRequest request)
    {
        var storeId = RequiredStoreId;
        var user = await dbContext.Users.AsNoTracking()
            .FirstOrDefaultAsync(u => u.Id == userId && u.StoreId == storeId);
        if (user == null)
            return NotFound(AppResponse<bool>.Error("Không tìm thấy tài khoản"));

        var granter = CurrentUserId.ToString();
        var dataScopePermId = await EnsureDataScopePermissionIdAsync();

        var oldBranches = await dbContext.BranchPermissions
            .Where(bp => bp.UserId == userId && (bp.StoreId == storeId || bp.StoreId == null))
            .ToListAsync();
        dbContext.BranchPermissions.RemoveRange(oldBranches);

        var oldDepts = await dbContext.DepartmentPermissions
            .Where(dp => dp.UserId == userId &&
                         dp.PermissionId == dataScopePermId &&
                         (dp.StoreId == storeId || dp.StoreId == null))
            .ToListAsync();
        dbContext.DepartmentPermissions.RemoveRange(oldDepts);

        if (request.AllBranches)
        {
            dbContext.BranchPermissions.Add(NewBranchPermission(
                userId, null, storeId, request.IncludeChildBranches, granter));
        }
        else
        {
            var branchIds = request.BranchIds.Distinct().ToList();
            var validBranchIds = await dbContext.Branches.AsNoTracking()
                .Where(b => b.StoreId == storeId && b.Deleted == null && branchIds.Contains(b.Id))
                .Select(b => b.Id)
                .ToListAsync();
            foreach (var id in validBranchIds)
            {
                dbContext.BranchPermissions.Add(NewBranchPermission(
                    userId, id, storeId, request.IncludeChildBranches, granter));
            }
        }

        if (request.AllDepartments)
        {
            dbContext.DepartmentPermissions.Add(NewDeptDataScope(
                userId, null, dataScopePermId, storeId, request.IncludeChildDepartments, granter));
        }
        else
        {
            var deptIds = request.DepartmentIds.Distinct().ToList();
            var validDeptIds = await dbContext.Departments.AsNoTracking()
                .Where(d => d.StoreId == storeId && d.Deleted == null && deptIds.Contains(d.Id))
                .Select(d => d.Id)
                .ToListAsync();
            foreach (var id in validDeptIds)
            {
                dbContext.DepartmentPermissions.Add(NewDeptDataScope(
                    userId, id, dataScopePermId, storeId, request.IncludeChildDepartments, granter));
            }
        }

        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<bool>.Success(true));
    }

    private async Task<Guid> EnsureDataScopePermissionIdAsync()
    {
        var existing = await dbContext.Permissions.AsNoTracking()
            .Where(p => p.Module == DataScopeModule)
            .Select(p => p.Id)
            .FirstOrDefaultAsync();
        if (existing != Guid.Empty) return existing;

        dbContext.Permissions.Add(new Permission
        {
            Id = DataScopePermissionId,
            Module = DataScopeModule,
            ModuleDisplayName = "Phạm vi dữ liệu",
            Description = "Chi nhánh / phòng ban tài khoản được xem dữ liệu",
            DisplayOrder = 999,
            CreatedAt = DateTime.UtcNow,
            CreatedBy = "system",
        });
        await dbContext.SaveChangesAsync();
        return DataScopePermissionId;
    }

    private static BranchPermission NewBranchPermission(
        Guid userId, Guid? branchId, Guid storeId, bool includeChildren, string granter) =>
        new()
        {
            Id = Guid.NewGuid(),
            UserId = userId,
            BranchId = branchId,
            StoreId = storeId,
            IncludeChildren = includeChildren,
            CanView = true,
            IsActive = true,
            GrantedBy = granter,
            CreatedAt = DateTime.UtcNow,
            CreatedBy = granter,
        };

    private static DepartmentPermission NewDeptDataScope(
        Guid userId, Guid? departmentId, Guid permissionId, Guid storeId,
        bool includeChildren, string granter) =>
        new()
        {
            Id = Guid.NewGuid(),
            UserId = userId,
            DepartmentId = departmentId,
            PermissionId = permissionId,
            StoreId = storeId,
            IncludeChildren = includeChildren,
            CanView = true,
            IsActive = true,
            GrantedBy = granter,
            CreatedAt = DateTime.UtcNow,
            CreatedBy = granter,
        };
}

public class SetAccountStatusRequest
{
    public bool IsActive { get; set; }
}

public class UpdateEmployeeAccountRequest
{
    public required string Email { get; set; }
    public required string FirstName { get; set; }
    public required string LastName { get; set; }
    public string? PhoneNumber { get; set; }
    public string? UserName { get; set; }
    public string? Role { get; set; }
}

public class UpdateProfileRequest
{
    public string? FirstName { get; set; }
    public string? LastName { get; set; }
    public string? PhoneNumber { get; set; }
}

public class UpdatePasswordRequest
{
    public required string CurrentPassword { get; set; }
    public required string NewPassword { get; set; }
}

public class ResetUserPasswordRequest
{
    public required string Password { get; set; }
}

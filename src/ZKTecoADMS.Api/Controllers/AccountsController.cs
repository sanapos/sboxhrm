using Mapster;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
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
using ZKTecoADMS.Application.DTOs.Employees;
using ZKTecoADMS.Application.DTOs.Accounts;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure;

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

        // Don't allow deleting store owner
        if (user.Id == CurrentUserId)
        {
            return Ok(AppResponse<bool>.Error("Không thể xóa tài khoản của chính mình"));
        }

        // Unlink employee record
        var employee = await dbContext.Employees
            .FirstOrDefaultAsync(e => e.ApplicationUserId == id, cancellationToken);
        if (employee != null)
        {
            employee.ApplicationUserId = null;
            dbContext.Employees.Update(employee);
        }

        // Reassign managed employees to current user
        var managedEmployees = await dbContext.Employees
            .Where(e => e.ManagerId == id)
            .ToListAsync(cancellationToken);
        foreach (var emp in managedEmployees)
        {
            emp.ManagerId = CurrentUserId;
            dbContext.Employees.Update(emp);
        }

        // Unlink managed users (set ManagerId to null)
        var managedUsers = await dbContext.Users
            .Where(u => u.ManagerId == id)
            .ToListAsync(cancellationToken);
        foreach (var u in managedUsers)
        {
            u.ManagerId = null;
        }

        await dbContext.SaveChangesAsync(cancellationToken);

        try
        {
            var result = await userManager.DeleteAsync(user);
            if (!result.Succeeded)
            {
                return Ok(AppResponse<bool>.Error(result.Errors.Select(e => e.Description).ToList()));
            }
        }
        catch (DbUpdateException)
        {
            return Ok(AppResponse<bool>.Error("Không thể xóa tài khoản vì còn dữ liệu liên quan (chấm công, phiếu lương...). Hãy vô hiệu hóa thay vì xóa."));
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

using ZKTecoADMS.Application.DTOs.Auth;
using ZKTecoADMS.Application.Interfaces.Auth;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;

namespace ZKTecoADMS.Application.Commands.Auth.AdminLogin;

/// <summary>
/// Handles admin login (SuperAdmin, Agent) without store code requirement.
/// </summary>
public class AdminLoginCommandHandler(
    UserManager<ApplicationUser> userManager,
    IAuthenticateService authenticateService
    ) : ICommandHandler<AdminLoginCommand, AppResponse<AuthenticateResponse>>
{
    public async Task<AppResponse<AuthenticateResponse>> Handle(AdminLoginCommand request, CancellationToken cancellationToken)
    {
        // Find user by username/email (no store check for admin)
        var user = await userManager.Users
            .Where(e => e.UserName == request.UserName || e.Email == request.UserName)
            .Include(e => e.Employee)
            .Include(e => e.Manager)
            .Include(e => e.Store)
            .FirstOrDefaultAsync(cancellationToken);
        
        if (user == null)
        {
            return AppResponse<AuthenticateResponse>.Error("Email không tồn tại.");
        }
        
        // Check if user has admin role (SuperAdmin or Agent)
        var roles = await userManager.GetRolesAsync(user);
        var isAdmin = roles.Contains(nameof(Roles.SuperAdmin)) || roles.Contains(nameof(Roles.Agent));
        
        if (!isAdmin)
        {
            return AppResponse<AuthenticateResponse>.Error("Tài khoản không có quyền truy cập Admin Portal.");
        }

        // Check if the user account is active
        if (!user.IsActive)
        {
            return AppResponse<AuthenticateResponse>.Error("Tài khoản đã bị vô hiệu hóa.");
        }
        
        // Check if the user's email is confirmed
        if (!await userManager.IsEmailConfirmedAsync(user))
        {
            return AppResponse<AuthenticateResponse>.Error("Email chưa được xác nhận.");
        }

        // Check if the user account is locked out
        if (await userManager.IsLockedOutAsync(user))
        {   
            return AppResponse<AuthenticateResponse>.Error("Tài khoản đã bị khóa.");
        }

        // Validate password
        var passwordValid = await userManager.CheckPasswordAsync(user, request.Password);
        if (!passwordValid)
        {
            await userManager.AccessFailedAsync(user);
            return AppResponse<AuthenticateResponse>.Error("Mật khẩu không đúng.");
        }

        // Reset failed login attempts on successful login
        await userManager.ResetAccessFailedCountAsync(user);

        // Generate tokens
        return await authenticateService.Authenticate(user, cancellationToken);
    }
}

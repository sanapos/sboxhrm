using ZKTecoADMS.Application.DTOs.Auth;
using ZKTecoADMS.Application.Helpers;
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
    RoleManager<IdentityRole<Guid>> roleManager,
    IAuthenticateService authenticateService
    ) : ICommandHandler<AdminLoginCommand, AppResponse<AuthenticateResponse>>
{
    public async Task<AppResponse<AuthenticateResponse>> Handle(AdminLoginCommand request, CancellationToken cancellationToken)
    {
        // Find user by username/email — không Include Employee/Store để tránh lỗi schema DB lệch migration.
        var user = await userManager.Users
            .Where(e => e.UserName == request.UserName || e.Email == request.UserName)
            .FirstOrDefaultAsync(cancellationToken);
        
        const string invalidCredentials = "Email hoặc mật khẩu không đúng.";
        if (user == null)
        {
            return AppResponse<AuthenticateResponse>.Error(invalidCredentials);
        }

        if (await userManager.IsLockedOutAsync(user))
        {
            return AppResponse<AuthenticateResponse>.Error(
                LockoutMessageHelper.GetLockedMessage(user, adminPortal: true));
        }

        // Kiểm tra mật khẩu trước — không để lộ email / vai trò / trạng thái cho người không biết mật khẩu.
        var passwordValid = await userManager.CheckPasswordAsync(user, request.Password);
        if (!passwordValid)
        {
            await userManager.AccessFailedAsync(user);
            var refreshed = await userManager.FindByIdAsync(user.Id.ToString());
            if (refreshed != null && await userManager.IsLockedOutAsync(refreshed))
            {
                return AppResponse<AuthenticateResponse>.Error(
                    LockoutMessageHelper.GetLockedMessage(refreshed, adminPortal: true));
            }
            return AppResponse<AuthenticateResponse>.Error(invalidCredentials);
        }

        // Self-heal: user.Role = SuperAdmin/Agent nhưng thiếu AspNetUserRoles (tạo tài khoản đại lý lỗi cũ).
        await IdentityRoleSyncHelper.TryHealAdminPortalRoleAsync(userManager, roleManager, user);

        var roles = await userManager.GetRolesAsync(user);
        var isAdmin = roles.Contains(nameof(Roles.SuperAdmin)) || roles.Contains(nameof(Roles.Agent));
        if (!isAdmin)
        {
            return AppResponse<AuthenticateResponse>.Error("Tài khoản không có quyền truy cập Admin Portal.");
        }

        if (!user.IsActive)
        {
            return AppResponse<AuthenticateResponse>.Error("Tài khoản đã bị vô hiệu hóa.");
        }

        if (!await userManager.IsEmailConfirmedAsync(user))
        {
            return AppResponse<AuthenticateResponse>.Error("Email chưa được xác nhận.");
        }

        // Reset failed login attempts on successful login
        await userManager.ResetAccessFailedCountAsync(user);

        // Generate tokens
        return await authenticateService.Authenticate(user, cancellationToken);
    }
}

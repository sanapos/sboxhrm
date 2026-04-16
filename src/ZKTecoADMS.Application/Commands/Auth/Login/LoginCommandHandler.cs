using ZKTecoADMS.Application.DTOs.Auth;
using ZKTecoADMS.Application.Interfaces.Auth;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Repositories;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;

namespace ZKTecoADMS.Application.Commands.Auth.Login;

/// <summary>
/// Handles user login without throwing exceptions.
/// Returns appropriate AppResponse with success/error status and messages.
/// Validates store code, email, password, account status, and generates JWT tokens on successful login.
/// </summary>
public class LoginCommandHandler(
    UserManager<ApplicationUser> userManager,
    IAuthenticateService authenticateService,
    IRepository<Store> storeRepository
    ) : ICommandHandler<LoginCommand, AppResponse<AuthenticateResponse>>
{
    public async Task<AppResponse<AuthenticateResponse>> Handle(LoginCommand request, CancellationToken cancellationToken)
    {
        // Tìm cửa hàng theo mã
        var store = await storeRepository.GetSingleAsync(
            s => s.Code.ToLower() == request.StoreCode.ToLower() && s.IsActive,
            cancellationToken: cancellationToken);
        
        if (store == null)
        {
            return AppResponse<AuthenticateResponse>.Error("Mã cửa hàng không tồn tại hoặc đã bị vô hiệu hóa.");
        }

        // First, find the user by username/email AND store (lightweight query for validation)
        // Hỗ trợ đăng nhập bằng cả UserName hoặc Email
        var user = await userManager.Users
            .Where(e => (e.UserName == request.UserName || e.Email == request.UserName || e.PhoneNumber == request.UserName) && e.StoreId == store.Id)
            .Include(e => e.Employee)
            .Include(e => e.Manager)
            .Include(e => e.Store)
            .FirstOrDefaultAsync(cancellationToken);
        
        if (user == null)
        {
            return AppResponse<AuthenticateResponse>.Error("Tài khoản không tồn tại trong cửa hàng này.");
        }

        // Check if the user account is active
        if (!user.IsActive)
        {
            return AppResponse<AuthenticateResponse>.Error("Tài khoản đã bị vô hiệu hóa. Vui lòng liên hệ quản trị viên.");
        }
        
        // Check if the user's email is confirmed (if required)
        if (!await userManager.IsEmailConfirmedAsync(user))
        {
            return AppResponse<AuthenticateResponse>.Error("Email chưa được xác nhận. Vui lòng kiểm tra email và xác nhận tài khoản.");
        }

        // Check if the user account is locked out
        if (await userManager.IsLockedOutAsync(user))
        {   
            return AppResponse<AuthenticateResponse>.Error("Tài khoản đã bị khóa. Vui lòng thử lại sau.");
        }

        // Validate password
        var passwordValid = await userManager.CheckPasswordAsync(user, request.Password);
        if (!passwordValid)
        {
            // Record failed login attempt
            await userManager.AccessFailedAsync(user);
            return AppResponse<AuthenticateResponse>.Error("Mật khẩu không đúng.");
        }

        // Reset failed login attempts on successful login
        await userManager.ResetAccessFailedCountAsync(user);

        // Generate tokens with fully loaded user entity (already loaded with includes above)
        return await authenticateService.Authenticate(user, cancellationToken);
    }
}
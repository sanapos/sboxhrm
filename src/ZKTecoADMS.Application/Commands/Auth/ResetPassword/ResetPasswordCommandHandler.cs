using ZKTecoADMS.Domain.Entities;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;

namespace ZKTecoADMS.Application.Commands.Auth.ResetPassword;

public class ResetPasswordCommandHandler(
    UserManager<ApplicationUser> userManager,
    ILogger<ResetPasswordCommandHandler> logger
) : ICommandHandler<ResetPasswordCommand, AppResponse<string>>
{
    public async Task<AppResponse<string>> Handle(ResetPasswordCommand request, CancellationToken cancellationToken)
    {
        // Tìm user theo email
        var user = await userManager.Users
            .Where(u => u.Email.ToLower() == request.Email.ToLower() || u.UserName.ToLower() == request.Email.ToLower())
            .FirstOrDefaultAsync(cancellationToken);
        
        if (user == null)
        {
            logger.LogWarning("ResetPassword: User not found for email {Email}", request.Email);
            return AppResponse<string>.Error("Token không hợp lệ hoặc đã hết hạn.");
        }

        // Decode token (URL encoded)
        var token = Uri.UnescapeDataString(request.Token);
        
        // Reset password
        var result = await userManager.ResetPasswordAsync(user, token, request.NewPassword);
        
        if (!result.Succeeded)
        {
            var errors = string.Join(", ", result.Errors.Select(e => e.Description));
            logger.LogWarning("ResetPassword: Failed to reset password for {Email}. Errors: {Errors}", request.Email, errors);
            
            // Check specific errors
            if (result.Errors.Any(e => e.Code == "InvalidToken"))
            {
                return AppResponse<string>.Error("Token không hợp lệ hoặc đã hết hạn. Vui lòng yêu cầu đặt lại mật khẩu mới.");
            }
            
            return AppResponse<string>.Error($"Không thể đặt lại mật khẩu: {errors}");
        }

        // Unlock account if locked
        if (await userManager.IsLockedOutAsync(user))
        {
            await userManager.SetLockoutEndDateAsync(user, null);
        }

        // Reset failed access count
        await userManager.ResetAccessFailedCountAsync(user);

        logger.LogInformation("ResetPassword: Password reset successfully for {Email}", request.Email);
        return AppResponse<string>.Success("Mật khẩu đã được đặt lại thành công. Vui lòng đăng nhập với mật khẩu mới.");
    }
}

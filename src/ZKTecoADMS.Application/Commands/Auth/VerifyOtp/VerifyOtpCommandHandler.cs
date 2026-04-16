using ZKTecoADMS.Application.Commands.Auth.ForgotPassword;
using ZKTecoADMS.Domain.Entities;
using Microsoft.AspNetCore.Identity;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Logging;

namespace ZKTecoADMS.Application.Commands.Auth.VerifyOtp;

public class VerifyOtpCommandHandler(
    UserManager<ApplicationUser> userManager,
    IMemoryCache memoryCache,
    ILogger<VerifyOtpCommandHandler> logger
) : ICommandHandler<VerifyOtpCommand, AppResponse<string>>
{
    public async Task<AppResponse<string>> Handle(VerifyOtpCommand request, CancellationToken cancellationToken)
    {
        var cacheKey = $"otp:{request.StoreCode.ToLower()}:{request.Email.ToLower()}";
        
        if (!memoryCache.TryGetValue<OtpEntry>(cacheKey, out var otpEntry))
        {
            return AppResponse<string>.Error("Mã OTP đã hết hạn. Vui lòng yêu cầu mã mới.");
        }

        if (otpEntry!.Otp != request.Otp)
        {
            return AppResponse<string>.Error("Mã OTP không đúng. Vui lòng kiểm tra lại.");
        }

        // OTP đúng - reset password bằng token đã lưu
        var user = await userManager.FindByIdAsync(otpEntry.UserId);
        if (user == null)
        {
            return AppResponse<string>.Error("Tài khoản không tồn tại.");
        }

        var result = await userManager.ResetPasswordAsync(user, otpEntry.ResetToken, request.NewPassword);
        if (!result.Succeeded)
        {
            var errors = string.Join(", ", result.Errors.Select(e => e.Description));
            logger.LogWarning("VerifyOtp: Failed to reset password for {Email}. Errors: {Errors}", request.Email, errors);
            return AppResponse<string>.Error($"Không thể đặt lại mật khẩu: {errors}");
        }

        // Xóa OTP khỏi cache
        memoryCache.Remove(cacheKey);

        // Mở khóa tài khoản nếu bị lock
        if (await userManager.IsLockedOutAsync(user))
        {
            await userManager.SetLockoutEndDateAsync(user, null);
        }
        await userManager.ResetAccessFailedCountAsync(user);

        logger.LogInformation("VerifyOtp: Password reset successfully for {Email}", request.Email);
        return AppResponse<string>.Success("Mật khẩu đã được đặt lại thành công. Vui lòng đăng nhập với mật khẩu mới.");
    }
}

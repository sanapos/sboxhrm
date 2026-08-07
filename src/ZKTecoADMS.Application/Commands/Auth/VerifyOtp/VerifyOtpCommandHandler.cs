using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
using Microsoft.AspNetCore.Identity;
using Microsoft.Extensions.Logging;

namespace ZKTecoADMS.Application.Commands.Auth.VerifyOtp;

public class VerifyOtpCommandHandler(
    UserManager<ApplicationUser> userManager,
    IPasswordOtpStore otpStore,
    ILogger<VerifyOtpCommandHandler> logger
) : ICommandHandler<VerifyOtpCommand, AppResponse<string>>
{
    private const int MaxFailedAttempts = 5;
    private static readonly TimeSpan OtpTtl = TimeSpan.FromMinutes(5);

    public async Task<AppResponse<string>> Handle(VerifyOtpCommand request, CancellationToken cancellationToken)
    {
        var otpEntry = await otpStore.GetAsync(request.StoreCode, request.Email, cancellationToken);
        if (otpEntry == null)
        {
            return AppResponse<string>.Error("Mã OTP đã hết hạn. Vui lòng yêu cầu mã mới.");
        }

        if (!string.Equals(otpEntry.Otp, request.Otp?.Trim(), StringComparison.Ordinal))
        {
            otpEntry.FailedAttempts++;
            if (otpEntry.FailedAttempts >= MaxFailedAttempts)
            {
                await otpStore.RemoveAsync(request.StoreCode, request.Email, cancellationToken);
                logger.LogWarning("VerifyOtp: Too many failed attempts for {Email}", request.Email);
                return AppResponse<string>.Error(
                    "Bạn đã nhập sai OTP quá nhiều lần. Vui lòng gửi lại mã mới.");
            }

            await otpStore.UpdateAsync(request.StoreCode, request.Email, otpEntry, OtpTtl, cancellationToken);
            var left = MaxFailedAttempts - otpEntry.FailedAttempts;
            return AppResponse<string>.Error($"Mã OTP không đúng. Còn {left} lần thử.");
        }

        var user = await userManager.FindByIdAsync(otpEntry.UserId);
        if (user == null)
        {
            await otpStore.RemoveAsync(request.StoreCode, request.Email, cancellationToken);
            return AppResponse<string>.Error("Tài khoản không tồn tại.");
        }

        var result = await userManager.ResetPasswordAsync(user, otpEntry.ResetToken, request.NewPassword);
        if (!result.Succeeded)
        {
            var errors = string.Join(", ", result.Errors.Select(MapPasswordError));
            logger.LogWarning("VerifyOtp: Failed to reset password for {Email}. Errors: {Errors}", request.Email, errors);
            return AppResponse<string>.Error($"Không thể đặt lại mật khẩu: {errors}");
        }

        await otpStore.RemoveAsync(request.StoreCode, request.Email, cancellationToken);

        if (await userManager.IsLockedOutAsync(user))
        {
            await userManager.SetLockoutEndDateAsync(user, null);
        }
        await userManager.ResetAccessFailedCountAsync(user);

        UserPasswordVisibility.ClearRememberedPassword(user);
        await userManager.UpdateAsync(user);

        logger.LogInformation("VerifyOtp: Password reset successfully for {Email}", request.Email);
        return AppResponse<string>.Success("Mật khẩu đã được đặt lại thành công. Vui lòng đăng nhập với mật khẩu mới.");
    }

    private static string MapPasswordError(IdentityError e) => e.Code switch
    {
        "PasswordTooShort" => "Mật khẩu quá ngắn (tối thiểu 6 ký tự)",
        "PasswordRequiresDigit" => "Mật khẩu cần có chữ số",
        "PasswordRequiresUpper" => "Mật khẩu cần có chữ hoa",
        "PasswordRequiresLower" => "Mật khẩu cần có chữ thường",
        "PasswordRequiresNonAlphanumeric" => "Mật khẩu cần có ký tự đặc biệt",
        "InvalidToken" => "Mã xác thực hết hạn. Vui lòng gửi lại OTP",
        _ => e.Description
    };
}

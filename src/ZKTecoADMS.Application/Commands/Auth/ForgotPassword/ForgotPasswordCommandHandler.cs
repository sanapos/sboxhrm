using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Repositories;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;

namespace ZKTecoADMS.Application.Commands.Auth.ForgotPassword;

public class ForgotPasswordCommandHandler(
    UserManager<ApplicationUser> userManager,
    IRepository<Store> storeRepository,
    IEmailService emailService,
    IPasswordOtpStore otpStore,
    ILogger<ForgotPasswordCommandHandler> logger
) : ICommandHandler<ForgotPasswordCommand, AppResponse<string>>
{
    private static readonly TimeSpan OtpTtl = TimeSpan.FromMinutes(5);
    private static readonly TimeSpan SendCooldown = TimeSpan.FromSeconds(60);

    public async Task<AppResponse<string>> Handle(ForgotPasswordCommand request, CancellationToken cancellationToken)
    {
        // Tìm cửa hàng theo mã
        var store = await storeRepository.GetSingleAsync(
            s => s.Code.ToLower() == request.StoreCode.ToLower() && s.IsActive,
            cancellationToken: cancellationToken);

        if (store == null)
        {
            logger.LogWarning("ForgotPassword: Store not found for code {StoreCode}", request.StoreCode);
            return AppResponse<string>.Success("Nếu email tồn tại trong hệ thống, chúng tôi đã gửi mã OTP xác nhận.");
        }

        // Tìm user theo email trong store
        var user = await userManager.Users
            .Where(u => (u.Email!.ToLower() == request.Email.ToLower() || u.UserName!.ToLower() == request.Email.ToLower())
                        && u.StoreId == store.Id)
            .FirstOrDefaultAsync(cancellationToken);

        if (user == null)
        {
            logger.LogWarning("ForgotPassword: User not found for email {Email} in store {StoreCode}", request.Email, request.StoreCode);
            return AppResponse<string>.Success("Nếu email tồn tại trong hệ thống, chúng tôi đã gửi mã OTP xác nhận.");
        }

        if (string.IsNullOrWhiteSpace(user.Email))
        {
            logger.LogWarning("ForgotPassword: User {UserId} has no email", user.Id);
            return AppResponse<string>.Error(
                "Tài khoản chưa có email. Vui lòng liên hệ quản trị viên để đặt lại mật khẩu.");
        }

        if (await otpStore.IsSendCooldownActiveAsync(request.StoreCode, request.Email, cancellationToken))
        {
            return AppResponse<string>.Error(
                "Vui lòng đợi khoảng 60 giây trước khi gửi lại mã OTP.");
        }

        // Tạo OTP 6 chữ số
        var otp = Random.Shared.Next(100000, 999999).ToString();

        // Tạo reset token và lưu cùng OTP (5 phút) — distributed cache
        var resetToken = await userManager.GeneratePasswordResetTokenAsync(user);
        await otpStore.SetAsync(
            request.StoreCode,
            request.Email,
            new PasswordOtpEntry
            {
                Otp = otp,
                ResetToken = resetToken,
                UserId = user.Id.ToString(),
                FailedAttempts = 0
            },
            OtpTtl,
            cancellationToken);

        var displayName = user.FullName ?? user.UserName ?? "User";
        var emailSent = await emailService.SendOtpEmailAsync(user.Email!, otp, displayName);

        if (!emailSent)
        {
            await otpStore.RemoveAsync(request.StoreCode, request.Email, cancellationToken);
            logger.LogError("ForgotPassword: Failed to send OTP email to {Email}", user.Email);
            return AppResponse<string>.Error("Không thể gửi email. Vui lòng thử lại sau hoặc liên hệ quản trị viên.");
        }

        await otpStore.MarkSendCooldownAsync(request.StoreCode, request.Email, SendCooldown, cancellationToken);

        logger.LogInformation("ForgotPassword: OTP sent to {Email} for store {StoreCode}", user.Email, request.StoreCode);
        return AppResponse<string>.Success("Chúng tôi đã gửi mã OTP đến email của bạn. Vui lòng kiểm tra hộp thư (và mục Spam).");
    }
}

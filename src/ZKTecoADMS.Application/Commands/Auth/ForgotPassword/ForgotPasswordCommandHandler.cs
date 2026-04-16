using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Repositories;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Logging;

namespace ZKTecoADMS.Application.Commands.Auth.ForgotPassword;

public class ForgotPasswordCommandHandler(
    UserManager<ApplicationUser> userManager,
    IRepository<Store> storeRepository,
    IEmailService emailService,
    IMemoryCache memoryCache,
    ILogger<ForgotPasswordCommandHandler> logger
) : ICommandHandler<ForgotPasswordCommand, AppResponse<string>>
{
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

        // Tạo OTP 6 chữ số
        var otp = Random.Shared.Next(100000, 999999).ToString();
        
        // Tạo reset token và lưu cùng OTP vào cache (5 phút)
        var resetToken = await userManager.GeneratePasswordResetTokenAsync(user);
        var cacheKey = $"otp:{request.StoreCode.ToLower()}:{request.Email.ToLower()}";
        memoryCache.Set(cacheKey, new OtpEntry(otp, resetToken, user.Id.ToString()), TimeSpan.FromMinutes(5));

        // Gửi OTP qua email
        var displayName = user.FullName ?? user.UserName ?? "User";
        var emailSent = await emailService.SendOtpEmailAsync(user.Email!, otp, displayName);
        
        if (!emailSent)
        {
            logger.LogError("ForgotPassword: Failed to send OTP email to {Email}", user.Email);
            return AppResponse<string>.Error("Không thể gửi email. Vui lòng thử lại sau.");
        }

        logger.LogInformation("ForgotPassword: OTP sent to {Email} for store {StoreCode}", user.Email, request.StoreCode);
        return AppResponse<string>.Success("Chúng tôi đã gửi mã OTP đến email của bạn. Vui lòng kiểm tra hộp thư.");
    }
}

public record OtpEntry(string Otp, string ResetToken, string UserId);

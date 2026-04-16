namespace ZKTecoADMS.Application.Interfaces;

public interface IEmailService
{
    /// <summary>
    /// Send password reset email to user
    /// </summary>
    Task<bool> SendPasswordResetEmailAsync(string email, string resetToken, string userName);
    
    /// <summary>
    /// Send welcome email after registration with account details
    /// </summary>
    Task<bool> SendWelcomeEmailAsync(string email, string storeName, string storeCode, string loginUrl);

    /// <summary>
    /// Send OTP code for password reset
    /// </summary>
    Task<bool> SendOtpEmailAsync(string email, string otpCode, string userName);

    /// <summary>
    /// Send generic email
    /// </summary>
    Task<bool> SendEmailAsync(string to, string subject, string body, bool isHtml = true);
}

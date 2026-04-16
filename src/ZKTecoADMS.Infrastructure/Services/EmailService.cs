using MailKit.Net.Smtp;
using MailKit.Security;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using MimeKit;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Settings;

namespace ZKTecoADMS.Infrastructure.Services;

public class EmailService : IEmailService
{
    private readonly EmailSettings _settings;
    private readonly ILogger<EmailService> _logger;

    public EmailService(IOptions<EmailSettings> settings, ILogger<EmailService> logger)
    {
        _settings = settings.Value;
        _logger = logger;
    }

    public async Task<bool> SendPasswordResetEmailAsync(string email, string resetToken, string userName)
    {
        var resetLink = $"{_settings.ResetPasswordBaseUrl}/reset-password?token={Uri.EscapeDataString(resetToken)}&email={Uri.EscapeDataString(email)}";
        
        var subject = "Đặt lại mật khẩu - ZKTeco ADMS";
        var body = $@"
        <html>
        <head>
            <style>
                body {{ font-family: Arial, sans-serif; line-height: 1.6; color: #333; }}
                .container {{ max-width: 600px; margin: 0 auto; padding: 20px; }}
                .header {{ background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 30px; text-align: center; border-radius: 10px 10px 0 0; }}
                .content {{ background: #f9f9f9; padding: 30px; border-radius: 0 0 10px 10px; }}
                .button {{ display: inline-block; background: #667eea; color: white !important; padding: 12px 30px; text-decoration: none; border-radius: 5px; margin: 20px 0; }}
                .footer {{ text-align: center; margin-top: 20px; color: #666; font-size: 12px; }}
                .warning {{ color: #e74c3c; font-size: 12px; }}
            </style>
        </head>
        <body>
            <div class='container'>
                <div class='header'>
                    <h1>🔐 Đặt lại mật khẩu</h1>
                </div>
                <div class='content'>
                    <p>Xin chào <strong>{userName}</strong>,</p>
                    <p>Bạn đã yêu cầu đặt lại mật khẩu cho tài khoản ZKTeco ADMS của mình.</p>
                    <p>Nhấn vào nút bên dưới để đặt lại mật khẩu:</p>
                    <p style='text-align: center;'>
                        <a href='{resetLink}' class='button'>Đặt lại mật khẩu</a>
                    </p>
                    <p>Hoặc copy link sau vào trình duyệt:</p>
                    <p style='word-break: break-all; background: #eee; padding: 10px; border-radius: 5px; font-size: 12px;'>{resetLink}</p>
                    <p class='warning'>⚠️ Link này sẽ hết hạn sau 1 giờ. Nếu bạn không yêu cầu đặt lại mật khẩu, vui lòng bỏ qua email này.</p>
                </div>
                <div class='footer'>
                    <p>© 2026 ZKTeco ADMS - Hệ thống quản lý chấm công</p>
                </div>
            </div>
        </body>
        </html>";

        return await SendEmailAsync(email, subject, body, true);
    }

    public async Task<bool> SendWelcomeEmailAsync(string email, string storeName, string storeCode, string loginUrl)
    {
        var subject = $"Chào mừng bạn đến với SBOX HRM - {storeName}";
        var body = $@"
        <html>
        <head>
            <style>
                body {{ font-family: Arial, sans-serif; line-height: 1.6; color: #333; }}
                .container {{ max-width: 600px; margin: 0 auto; padding: 20px; }}
                .header {{ background: linear-gradient(135deg, #0C56D0 0%, #1E3A5F 100%); color: white; padding: 30px; text-align: center; border-radius: 10px 10px 0 0; }}
                .content {{ background: #f9f9f9; padding: 30px; border-radius: 0 0 10px 10px; }}
                .info-box {{ background: #fff; border: 1px solid #e0e0e0; border-radius: 8px; padding: 20px; margin: 16px 0; }}
                .info-row {{ display: flex; padding: 8px 0; border-bottom: 1px solid #f0f0f0; }}
                .info-label {{ font-weight: bold; color: #555; min-width: 120px; }}
                .info-value {{ color: #0C56D0; font-weight: 600; }}
                .button {{ display: inline-block; background: #0C56D0; color: white !important; padding: 14px 36px; text-decoration: none; border-radius: 8px; margin: 20px 0; font-weight: 600; }}
                .footer {{ text-align: center; margin-top: 20px; color: #666; font-size: 12px; }}
                .warning {{ color: #e67e22; font-size: 13px; background: #fef9e7; padding: 12px; border-radius: 6px; margin-top: 16px; }}
            </style>
        </head>
        <body>
            <div class='container'>
                <div class='header'>
                    <h1>🎉 Đăng ký thành công!</h1>
                    <p style='margin: 0; opacity: 0.9;'>Chào mừng bạn đến với SBOX HRM</p>
                </div>
                <div class='content'>
                    <p>Xin chào,</p>
                    <p>Tài khoản của bạn đã được tạo thành công. Dưới đây là thông tin đăng nhập:</p>
                    
                    <div class='info-box'>
                        <table style='width:100%;border-collapse:collapse;'>
                            <tr><td style='padding:8px 0;font-weight:bold;color:#555;'>Tên cửa hàng:</td><td style='padding:8px 0;color:#0C56D0;font-weight:600;'>{storeName}</td></tr>
                            <tr style='border-top:1px solid #f0f0f0;'><td style='padding:8px 0;font-weight:bold;color:#555;'>Mã cửa hàng:</td><td style='padding:8px 0;color:#0C56D0;font-weight:600;font-size:18px;'>{storeCode}</td></tr>
                            <tr style='border-top:1px solid #f0f0f0;'><td style='padding:8px 0;font-weight:bold;color:#555;'>Email đăng nhập:</td><td style='padding:8px 0;color:#0C56D0;font-weight:600;'>{email}</td></tr>
                            <tr style='border-top:1px solid #f0f0f0;'><td style='padding:8px 0;font-weight:bold;color:#555;'>Vai trò:</td><td style='padding:8px 0;color:#059669;font-weight:600;'>Admin (Quản trị viên)</td></tr>
                        </table>
                    </div>

                    <p style='text-align: center;'>
                        <a href='{loginUrl}' class='button'>Đăng nhập ngay</a>
                    </p>

                    <div class='warning'>
                        ⚠️ <strong>Lưu ý bảo mật:</strong> Vui lòng ghi nhớ mã cửa hàng <strong>{storeCode}</strong> để đăng nhập. Không chia sẻ mật khẩu với người khác.
                    </div>
                </div>
                <div class='footer'>
                    <p>© 2026 SBOX HRM - Hệ thống quản lý nhân sự</p>
                </div>
            </div>
        </body>
        </html>";

        return await SendEmailAsync(email, subject, body, true);
    }

    public async Task<bool> SendOtpEmailAsync(string email, string otpCode, string userName)
    {
        var subject = "Mã xác nhận đặt lại mật khẩu - SBOX HRM";
        var body = $@"
        <html>
        <head>
            <style>
                body {{ font-family: Arial, sans-serif; line-height: 1.6; color: #333; }}
                .container {{ max-width: 600px; margin: 0 auto; padding: 20px; }}
                .header {{ background: linear-gradient(135deg, #0C56D0 0%, #1E3A5F 100%); color: white; padding: 30px; text-align: center; border-radius: 10px 10px 0 0; }}
                .content {{ background: #f9f9f9; padding: 30px; border-radius: 0 0 10px 10px; }}
                .otp-box {{ background: #fff; border: 2px dashed #0C56D0; border-radius: 12px; padding: 24px; text-align: center; margin: 24px 0; }}
                .otp-code {{ font-size: 36px; font-weight: 700; letter-spacing: 12px; color: #0C56D0; margin: 0; }}
                .footer {{ text-align: center; margin-top: 20px; color: #666; font-size: 12px; }}
                .warning {{ color: #e74c3c; font-size: 12px; }}
            </style>
        </head>
        <body>
            <div class='container'>
                <div class='header'>
                    <h1>🔐 Mã xác nhận OTP</h1>
                </div>
                <div class='content'>
                    <p>Xin chào <strong>{userName}</strong>,</p>
                    <p>Bạn đã yêu cầu đặt lại mật khẩu. Vui lòng sử dụng mã OTP bên dưới:</p>
                    
                    <div class='otp-box'>
                        <p class='otp-code'>{otpCode}</p>
                    </div>

                    <p style='text-align:center;color:#555;'>Nhập mã này vào ứng dụng để xác nhận đặt lại mật khẩu.</p>
                    
                    <p class='warning'>⚠️ Mã OTP có hiệu lực trong <strong>5 phút</strong>. Nếu bạn không yêu cầu đặt lại mật khẩu, vui lòng bỏ qua email này.</p>
                </div>
                <div class='footer'>
                    <p>© 2026 SBOX HRM - Hệ thống quản lý nhân sự</p>
                </div>
            </div>
        </body>
        </html>";

        return await SendEmailAsync(email, subject, body, true);
    }

    public async Task<bool> SendEmailAsync(string to, string subject, string body, bool isHtml = true)
    {
        try
        {
            var message = new MimeMessage();
            message.From.Add(new MailboxAddress(_settings.FromName, _settings.FromEmail));
            message.To.Add(new MailboxAddress(to, to));
            message.Subject = subject;

            var bodyBuilder = new BodyBuilder();
            if (isHtml)
            {
                bodyBuilder.HtmlBody = body;
            }
            else
            {
                bodyBuilder.TextBody = body;
            }
            message.Body = bodyBuilder.ToMessageBody();

            using var client = new SmtpClient();
            
            await client.ConnectAsync(_settings.SmtpHost, _settings.SmtpPort, 
                _settings.EnableSsl ? SecureSocketOptions.StartTls : SecureSocketOptions.None);
            
            await client.AuthenticateAsync(_settings.SmtpUsername, _settings.SmtpPassword);
            await client.SendAsync(message);
            await client.DisconnectAsync(true);

            _logger.LogInformation("Email sent successfully to {Email}", to);
            return true;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to send email to {Email}", to);
            return false;
        }
    }
}

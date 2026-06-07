using Microsoft.Extensions.Logging;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Infrastructure.Services.Channels;

/// <summary>Email channel — dùng IEmailService có sẵn (SMTP).</summary>
public class EmailChannelProvider : INotificationChannelProvider
{
    private readonly IEmailService _email;
    private readonly ILogger<EmailChannelProvider> _logger;

    public EmailChannelProvider(IEmailService email, ILogger<EmailChannelProvider> logger)
    {
        _email = email; _logger = logger;
    }

    public NotificationChannel Channel => NotificationChannel.Email;
    public bool IsConfigured => true; // EmailService tự kiểm tra config; nếu chưa setup sẽ trả false ở SendAsync

    public async Task<ChannelSendResult> SendAsync(ChannelRecipient r, string title, string body, string? actionUrl, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(r.Email))
            return new ChannelSendResult(false, "Người nhận không có email");
        try
        {
            var html = BuildHtml(title, body, actionUrl);
            var ok = await _email.SendEmailAsync(r.Email!, title, html, isHtml: true);
            return new ChannelSendResult(ok, ok ? null : "SMTP returned false");
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Email send failed to {Email}", r.Email);
            return new ChannelSendResult(false, ex.Message);
        }
    }

    private static string BuildHtml(string title, string body, string? actionUrl)
    {
        var safeTitle = System.Net.WebUtility.HtmlEncode(title);
        var safeBody = System.Net.WebUtility.HtmlEncode(body).Replace("\n", "<br/>");
        var actionHtml = string.IsNullOrWhiteSpace(actionUrl)
            ? string.Empty
            : $"<p><a href=\"{System.Net.WebUtility.HtmlEncode(actionUrl)}\" style=\"display:inline-block;padding:10px 20px;background:#1E3A5F;color:#fff;border-radius:6px;text-decoration:none\">Xem chi tiết</a></p>";
        return $"""
                <!doctype html><html><body style="font-family:Segoe UI,Arial,sans-serif;background:#f5f7fa;padding:24px">
                <div style="max-width:560px;margin:0 auto;background:#fff;border-radius:8px;padding:24px;box-shadow:0 1px 3px rgba(0,0,0,.08)">
                    <h2 style="color:#1E3A5F;margin:0 0 12px">{safeTitle}</h2>
                    <p style="color:#333;line-height:1.6">{safeBody}</p>
                    {actionHtml}
                    <hr style="border:none;border-top:1px solid #eee;margin:16px 0"/>
                    <p style="font-size:12px;color:#888">Đây là thông báo tự động từ hệ thống ZKTecoADMS. Vui lòng không trả lời email này.</p>
                </div>
                </body></html>
                """;
    }
}

/// <summary>SMS channel — stub cho P3. Tích hợp eSMS / Twilio sẽ làm ở giai đoạn sau.</summary>
public class SmsChannelProvider : INotificationChannelProvider
{
    private readonly ILogger<SmsChannelProvider> _logger;
    public SmsChannelProvider(ILogger<SmsChannelProvider> logger) { _logger = logger; }

    public NotificationChannel Channel => NotificationChannel.Sms;
    public bool IsConfigured => false;

    public Task<ChannelSendResult> SendAsync(ChannelRecipient r, string title, string body, string? actionUrl, CancellationToken ct = default)
    {
        _logger.LogInformation("📱 [SMS-STUB] To={Phone} | {Title}", r.Phone, title);
        return Task.FromResult(new ChannelSendResult(false, "SMS provider chưa được cấu hình (TODO)"));
    }
}

/// <summary>Push (FCM) channel — dùng <see cref="Push.IPushNotificationService"/> (Firebase Admin).</summary>
public class PushChannelProvider : INotificationChannelProvider
{
    private readonly Push.IPushNotificationService _push;
    private readonly Push.FirebaseInitializer _firebase;
    private readonly ILogger<PushChannelProvider> _logger;

    public PushChannelProvider(
        Push.IPushNotificationService push,
        Push.FirebaseInitializer firebase,
        ILogger<PushChannelProvider> logger)
    {
        _push = push;
        _firebase = firebase;
        _logger = logger;
    }

    public NotificationChannel Channel => NotificationChannel.Push;
    public bool IsConfigured => _firebase.IsAvailable;

    public async Task<ChannelSendResult> SendAsync(
        ChannelRecipient r, string title, string body, string? actionUrl, CancellationToken ct = default)
    {
        if (!IsConfigured)
            return new ChannelSendResult(false, "Firebase chưa được cấu hình");

        try
        {
            var data = new Dictionary<string, string>
            {
                ["relatedEntityType"] = "SystemAnnouncement",
            };
            if (!string.IsNullOrEmpty(actionUrl))
                data["actionUrl"] = actionUrl;

            var sent = await _push.PushToUserAsync(r.UserId, title, body, actionUrl, data, ct: ct);
            if (sent > 0)
                return new ChannelSendResult(true, null);

            _logger.LogInformation(
                "🔔 Announcement FCM: no active tokens for user {UserId}", r.UserId);
            return new ChannelSendResult(false, "Người nhận chưa đăng ký thiết bị push");
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Announcement FCM failed for user {UserId}", r.UserId);
            return new ChannelSendResult(false, ex.Message);
        }
    }
}

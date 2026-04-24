namespace ZKTecoADMS.Application.Interfaces;

/// <summary>
/// Một người nhận đã được audience-resolver giải quyết (đầy đủ contact info để gửi multi-channel).
/// </summary>
public sealed record ChannelRecipient(
    Guid UserId,
    string? Email,
    string? Phone,
    string? FcmToken,
    string DisplayName,
    Guid? StoreId);

public sealed record ChannelSendResult(bool Success, string? ErrorMessage);

/// <summary>
/// Một kênh phát thông báo (Email / Sms / Push). Triển khai theo Strategy pattern,
/// được DI inject bằng key (kênh nào hỗ trợ gì).
/// </summary>
public interface INotificationChannelProvider
{
    /// <summary>Kênh mà provider này phục vụ.</summary>
    Domain.Enums.NotificationChannel Channel { get; }

    /// <summary>Có sẵn sàng gửi (đã cấu hình credentials)?</summary>
    bool IsConfigured { get; }

    Task<ChannelSendResult> SendAsync(
        ChannelRecipient recipient,
        string title,
        string body,
        string? actionUrl,
        CancellationToken ct = default);
}

namespace ZKTecoADMS.Application.Interfaces;

/// <summary>
/// Thu hồi thông báo nhắc gia hạn khi license thay đổi và dọn announcement renewal cũ.
/// </summary>
public interface IRenewalNotificationService
{
    /// <summary>
    /// Ẩn banner renewal + đánh dấu notification cũ sau khi gia hạn/kích hoạt license.
    /// </summary>
    Task InvalidateForStoreAsync(
        Guid storeId,
        string storeName,
        DateTime? newExpiryDate,
        bool sendSuccessNotification,
        CancellationToken ct = default);

    /// <summary>
    /// Dismiss mọi renewal announcement cũ của store trước khi gửi mốc mới (chỉ giữ 1 active).
    /// </summary>
    Task DismissPendingRenewalAnnouncementsAsync(Guid storeId, CancellationToken ct = default);

    /// <summary>
    /// Dọn renewal stale: store đã gia hạn xa nhưng banner/notification còn sót.
    /// </summary>
    Task CleanupStaleRenewalAlertsAsync(CancellationToken ct = default);
}

using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Background service tự động xóa thông báo:
/// - Đã đọc: xóa sau 30 ngày
/// - Chưa đọc: xóa sau 90 ngày
/// Chạy mỗi 24 giờ.
/// </summary>
public class NotificationCleanupBackgroundService : BackgroundService
{
    private readonly IServiceProvider _serviceProvider;
    private readonly ILogger<NotificationCleanupBackgroundService> _logger;
    private readonly TimeSpan _checkInterval = TimeSpan.FromHours(24);
    private const int ReadRetentionDays = 30;
    private const int UnreadRetentionDays = 90;

    public NotificationCleanupBackgroundService(
        IServiceProvider serviceProvider,
        ILogger<NotificationCleanupBackgroundService> logger)
    {
        _serviceProvider = serviceProvider;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("🧹 Notification Cleanup Background Service started (read: {ReadDays}d, unread: {UnreadDays}d)",
            ReadRetentionDays, UnreadRetentionDays);

        // Wait for app startup
        await Task.Delay(TimeSpan.FromMinutes(2), stoppingToken);

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await CleanupOldNotificationsAsync(stoppingToken);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error in notification cleanup service");
            }

            await Task.Delay(_checkInterval, stoppingToken);
        }

        _logger.LogInformation("🧹 Notification Cleanup Background Service stopped");
    }

    private async Task CleanupOldNotificationsAsync(CancellationToken stoppingToken)
    {
        using var scope = _serviceProvider.CreateScope();
        var notificationRepository = scope.ServiceProvider.GetRequiredService<IRepository<Notification>>();

        var readCutoff = DateTime.UtcNow.AddDays(-ReadRetentionDays);
        var unreadCutoff = DateTime.UtcNow.AddDays(-UnreadRetentionDays);

        // Count for logging
        var readCount = await notificationRepository.CountAsync(
            n => n.IsRead && n.CreatedAt < readCutoff, stoppingToken);
        var unreadCount = await notificationRepository.CountAsync(
            n => !n.IsRead && n.CreatedAt < unreadCutoff, stoppingToken);

        if (readCount == 0 && unreadCount == 0)
        {
            _logger.LogDebug("No old notifications to clean up");
            return;
        }

        // Delete read notifications older than 30 days
        if (readCount > 0)
        {
            await notificationRepository.DeleteAsync(
                n => n.IsRead && n.CreatedAt < readCutoff, stoppingToken);
        }

        // Delete unread notifications older than 90 days
        if (unreadCount > 0)
        {
            await notificationRepository.DeleteAsync(
                n => !n.IsRead && n.CreatedAt < unreadCutoff, stoppingToken);
        }

        _logger.LogInformation("🧹 Cleaned up {ReadCount} read (>{ReadDays}d) + {UnreadCount} unread (>{UnreadDays}d) notifications",
            readCount, ReadRetentionDays, unreadCount, UnreadRetentionDays);
    }
}

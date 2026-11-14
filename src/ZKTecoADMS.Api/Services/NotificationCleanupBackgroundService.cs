using Microsoft.EntityFrameworkCore;
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

        // Use Notification.Timestamp (UTC) rather than Entity.CreatedAt (DateTime.Now
        // = SERVER LOCAL TIME). On a non-UTC server those two diverge by the local
        // offset, which used to delete notifications a full timezone-offset earlier
        // or later than the configured retention window.
        var readCutoff = DateTime.UtcNow.AddDays(-ReadRetentionDays);
        var unreadCutoff = DateTime.UtcNow.AddDays(-UnreadRetentionDays);

        var readCount = await notificationRepository.CountAsync(
            n => n.IsRead && n.Timestamp < readCutoff, stoppingToken);
        var unreadCount = await notificationRepository.CountAsync(
            n => !n.IsRead && n.Timestamp < unreadCutoff, stoppingToken);

        if (readCount == 0 && unreadCount == 0)
        {
            _logger.LogDebug("No old notifications to clean up");
            return;
        }

        // Xóa theo lô ngay trong CSDL. Trước đây nạp TOÀN BỘ thông báo hết hạn vào bộ nhớ rồi xóa từng dòng trong một
        // giao dịch: vài trăm nghìn dòng là tốn hàng GB RAM và khóa bảng rất lâu.
        var db = scope.ServiceProvider.GetRequiredService<ZKTecoADMS.Infrastructure.ZKTecoDbContext>();
        async Task DeleteInBatchesAsync(System.Linq.Expressions.Expression<Func<Notification, bool>> expired)
        {
            const int batch = 5000;
            for (var round = 0; round < 2000 && !stoppingToken.IsCancellationRequested; round++)
            {
                var ids = await db.Notifications.AsNoTracking()
                    .Where(expired)
                    .OrderBy(n => n.Timestamp)
                    .Select(n => n.Id)
                    .Take(batch)
                    .ToListAsync(stoppingToken);
                if (ids.Count == 0) break;
                await db.Notifications.Where(n => ids.Contains(n.Id)).ExecuteDeleteAsync(stoppingToken);
                if (ids.Count < batch) break;
            }
        }

        if (readCount > 0)
            await DeleteInBatchesAsync(n => n.IsRead && n.Timestamp < readCutoff);

        if (unreadCount > 0)
            await DeleteInBatchesAsync(n => !n.IsRead && n.Timestamp < unreadCutoff);

        _logger.LogInformation("🧹 Cleaned up {ReadCount} read (>{ReadDays}d) + {UnreadCount} unread (>{UnreadDays}d) notifications",
            readCount, ReadRetentionDays, unreadCount, UnreadRetentionDays);
    }
}

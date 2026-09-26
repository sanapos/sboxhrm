using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Controllers.Filters;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Services;

/// <summary>Xóa Lịch sử thao tác của cửa hàng cũ hơn 30 ngày (chạy mỗi 6 giờ). Không đụng nhật ký quản trị hệ thống.</summary>
public class ActivityLogCleanupService(IServiceProvider services, ILogger<ActivityLogCleanupService> logger) : BackgroundService
{
    public const int RetentionDays = 30;

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        await Task.Delay(TimeSpan.FromMinutes(3), stoppingToken);
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                using var scope = services.CreateScope();
                var db = scope.ServiceProvider.GetRequiredService<ZKTecoDbContext>();
                var cutoff = DateTime.UtcNow.AddDays(-RetentionDays);
                var marker = $"\"source\":\"{ActivityAuditFilter.Source}\"";
                var removed = await db.AuditLogs.IgnoreQueryFilters()
                    .Where(a => a.StoreId != null && a.Timestamp < cutoff && a.Details != null && a.Details.Contains(marker))
                    .ExecuteDeleteAsync(stoppingToken);
                if (removed > 0) logger.LogInformation("Activity log cleanup: removed {Count} entries older than {Days} days", removed, RetentionDays);
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                logger.LogWarning(ex, "Activity log cleanup failed");
            }
            await Task.Delay(TimeSpan.FromHours(6), stoppingToken);
        }
    }
}

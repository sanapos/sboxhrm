namespace ZKTecoADMS.Api.Services;

using ZKTecoADMS.Application.Interfaces;

/// <summary>
/// Dọn renewal announcement/notification còn sót khi store đã gia hạn xa (T+30).
/// Chạy mỗi 6 giờ.
/// </summary>
public class RenewalStaleCleanupBackgroundService : BackgroundService
{
    private readonly IServiceProvider _sp;
    private readonly ILogger<RenewalStaleCleanupBackgroundService> _logger;
    private readonly TimeSpan _interval = TimeSpan.FromHours(6);

    public RenewalStaleCleanupBackgroundService(
        IServiceProvider sp,
        ILogger<RenewalStaleCleanupBackgroundService> logger)
    {
        _sp = sp;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("Renewal stale cleanup service started");
        await Task.Delay(TimeSpan.FromMinutes(5), stoppingToken);

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                using var scope = _sp.CreateScope();
                var svc = scope.ServiceProvider.GetRequiredService<IRenewalNotificationService>();
                await svc.CleanupStaleRenewalAlertsAsync(stoppingToken);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Renewal stale cleanup failed");
            }

            await Task.Delay(_interval, stoppingToken);
        }
    }
}

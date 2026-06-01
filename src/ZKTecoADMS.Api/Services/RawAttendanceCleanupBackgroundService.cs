using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Tự động xóa chấm công thô cũ hơn N ngày (mặc định 180) theo thiết lập từng cửa hàng.
/// </summary>
public class RawAttendanceCleanupBackgroundService : BackgroundService
{
    private const int DefaultRetentionDays = 180;
    private readonly IServiceProvider _serviceProvider;
    private readonly ILogger<RawAttendanceCleanupBackgroundService> _logger;
    private readonly TimeSpan _checkInterval = TimeSpan.FromHours(24);

    public RawAttendanceCleanupBackgroundService(
        IServiceProvider serviceProvider,
        ILogger<RawAttendanceCleanupBackgroundService> logger)
    {
        _serviceProvider = serviceProvider;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation(
            "Raw attendance cleanup started (default retention: {Days} days)",
            DefaultRetentionDays);

        await Task.Delay(TimeSpan.FromMinutes(10), stoppingToken);

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await CleanupAsync(stoppingToken);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error in raw attendance cleanup service");
            }

            await Task.Delay(_checkInterval, stoppingToken);
        }
    }

    private async Task CleanupAsync(CancellationToken stoppingToken)
    {
        using var scope = _serviceProvider.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<ZKTecoDbContext>();

        var storeIds = await db.Devices
            .Where(d => d.StoreId != null)
            .Select(d => d.StoreId!.Value)
            .Distinct()
            .ToListAsync(stoppingToken);

        var retentionSettings = await db.AppSettings
            .Where(s => s.Key == AppSettingKeys.RawAttendanceRetentionDays && s.StoreId != null)
            .ToListAsync(stoppingToken);

        var retentionByStore = retentionSettings
            .GroupBy(s => s.StoreId!.Value)
            .ToDictionary(
                g => g.Key,
                g => int.TryParse(g.OrderByDescending(x => x.UpdatedAt).First().Value, out var days) && days > 0
                    ? days
                    : DefaultRetentionDays);

        var totalDeleted = 0;

        foreach (var storeId in storeIds)
        {
            var retentionDays = retentionByStore.GetValueOrDefault(storeId, DefaultRetentionDays);
            var cutoff = DateTime.Now.AddDays(-retentionDays);

            var deleted = await db.AttendanceLogs
                .Where(a => a.Device.StoreId == storeId && a.AttendanceTime < cutoff)
                .ExecuteDeleteAsync(stoppingToken);

            if (deleted > 0)
            {
                totalDeleted += deleted;
                _logger.LogInformation(
                    "Deleted {Count} raw attendance records for store {StoreId} older than {Days} days (before {Cutoff:yyyy-MM-dd})",
                    deleted, storeId, retentionDays, cutoff);
            }
        }

        if (totalDeleted > 0)
        {
            _logger.LogInformation("Raw attendance cleanup finished: {Total} records removed", totalDeleted);
        }
    }
}

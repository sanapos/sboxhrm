using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.DTOs.SystemAdmin;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Quét các SystemAnnouncement có Status=Scheduled & ScheduleAt &lt;= now và gọi SendAsync.
/// Chạy mỗi 60s.
/// </summary>
public class ScheduledAnnouncementBackgroundService : BackgroundService
{
    private readonly IServiceProvider _sp;
    private readonly ILogger<ScheduledAnnouncementBackgroundService> _logger;
    private readonly TimeSpan _interval = TimeSpan.FromSeconds(60);

    public ScheduledAnnouncementBackgroundService(IServiceProvider sp, ILogger<ScheduledAnnouncementBackgroundService> logger)
    {
        _sp = sp; _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("📅 ScheduledAnnouncement service started");
        await Task.Delay(TimeSpan.FromSeconds(30), stoppingToken);
        while (!stoppingToken.IsCancellationRequested)
        {
            try { await RunOnceAsync(stoppingToken); }
            catch (Exception ex) { _logger.LogError(ex, "ScheduledAnnouncement run failed"); }
            await Task.Delay(_interval, stoppingToken);
        }
    }

    private async Task RunOnceAsync(CancellationToken ct)
    {
        using var scope = _sp.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<ZKTecoDbContext>();
        var svc = scope.ServiceProvider.GetRequiredService<IAnnouncementService>();
        var now = DateTime.UtcNow;
        var due = await db.SystemAnnouncements.AsNoTracking()
            .Where(x => x.Status == AnnouncementStatus.Scheduled && x.ScheduleAt != null && x.ScheduleAt <= now)
            .Select(x => x.Id)
            .Take(50)
            .ToListAsync(ct);
        foreach (var id in due)
        {
            try
            {
                var n = await svc.SendAsync(id, ct);
                _logger.LogInformation("Sent scheduled announcement {Id} → {N} recipients", id, n);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Failed to send scheduled announcement {Id}", id);
            }
        }
    }
}

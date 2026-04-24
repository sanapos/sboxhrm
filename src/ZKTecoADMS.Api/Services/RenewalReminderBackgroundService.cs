using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.DTOs.SystemAdmin;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Tự động gửi nhắc gia hạn cho các Store có ExpiryDate sắp tới (30/15/7/3/1 ngày).
/// Chạy mỗi 6 giờ. Tránh gửi trùng bằng cách kiểm tra Title pattern trong 24h gần nhất.
/// </summary>
public class RenewalReminderBackgroundService : BackgroundService
{
    private readonly IServiceProvider _sp;
    private readonly ILogger<RenewalReminderBackgroundService> _logger;
    private readonly TimeSpan _interval = TimeSpan.FromHours(6);
    private static readonly int[] Thresholds = { 30, 15, 7, 3, 1 };

    public RenewalReminderBackgroundService(IServiceProvider sp, ILogger<RenewalReminderBackgroundService> logger)
    {
        _sp = sp; _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("⏰ RenewalReminder service started");
        await Task.Delay(TimeSpan.FromMinutes(3), stoppingToken);
        while (!stoppingToken.IsCancellationRequested)
        {
            try { await RunOnceAsync(stoppingToken); }
            catch (Exception ex) { _logger.LogError(ex, "RenewalReminder run failed"); }
            await Task.Delay(_interval, stoppingToken);
        }
    }

    private async Task RunOnceAsync(CancellationToken ct)
    {
        using var scope = _sp.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<ZKTecoDbContext>();
        var svc = scope.ServiceProvider.GetRequiredService<IAnnouncementService>();
        var today = DateTime.UtcNow.Date;

        foreach (var d in Thresholds)
        {
            var dayStart = today.AddDays(d);
            var dayEnd = dayStart.AddDays(1);
            var stores = await db.Stores.AsNoTracking()
                .IgnoreQueryFilters()
                .Where(s => s.ExpiryDate != null && s.ExpiryDate >= dayStart && s.ExpiryDate < dayEnd)
                .Select(s => new { s.Id, s.Name, s.ExpiryDate })
                .ToListAsync(ct);

            foreach (var s in stores)
            {
                var marker = $"[RENEWAL-{d}D-{s.Id:N}]";
                var since = DateTime.UtcNow.AddHours(-23);
                var dup = await db.SystemAnnouncements.AsNoTracking()
                    .AnyAsync(a => a.CreatedAt >= since && a.Title.Contains(marker), ct);
                if (dup) continue;

                try
                {
                    await svc.CreateAsync(new CreateSystemAnnouncementDto
                    {
                        Title = $"⏰ {s.Name}: license còn {d} ngày {marker}",
                        Content = $"Cửa hàng \"{s.Name}\" có license sẽ hết hạn vào {s.ExpiryDate:dd/MM/yyyy}. Vui lòng liên hệ đại lý / nhà cung cấp để gia hạn.",
                        Kind = AnnouncementKind.Renewal,
                        Severity = d <= 3 ? AnnouncementSeverity.Critical : AnnouncementSeverity.Warning,
                        Channels = NotificationChannel.InApp | NotificationChannel.Banner,
                        RequireAck = d <= 1,
                        AllowDismiss = d > 3,
                        Audience = new AudienceSpec
                        {
                            AllUsers = false,
                            StoreIds = new List<Guid> { s.Id }
                        },
                        SendNow = true,
                        ExpiresAt = s.ExpiryDate
                    }, Guid.Empty, ct);
                    _logger.LogInformation("Sent renewal reminder T-{D} for store {Store}", d, s.Name);
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Failed renewal reminder T-{D} store {Store}", d, s.Id);
                }
            }
        }
    }
}

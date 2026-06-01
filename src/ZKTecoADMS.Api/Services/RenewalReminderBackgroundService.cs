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
            var targetDay = today.AddDays(d);
            var stores = await db.Stores.AsNoTracking()
                .IgnoreQueryFilters()
                .Where(s => s.ExpiryDate != null
                    && s.ExpiryDate.Value.Date == targetDay)
                .Select(s => new { s.Id, s.Name, s.ExpiryDate })
                .ToListAsync(ct);

            foreach (var s in stores)
            {
                // Marker được nhúng vào Content (cuối) thay vì Title để không lộ ra UI.
                var marker = $"[RENEWAL-{d}D-{s.Id:N}]";
                var since = DateTime.UtcNow.AddHours(-23);
                var dup = await db.SystemAnnouncements.AsNoTracking()
                    .AnyAsync(a => a.CreatedAt >= since && (a.Title.Contains(marker) || a.Content.Contains(marker)), ct);
                if (dup) continue;

                try
                {
                    // Title: ngắn gọn, không kèm marker. Frontend sẽ tự tính lại số ngày từ ExpiresAt.
                    var title = $"⏰ {s.Name}: license sắp hết hạn ({d} ngày)";
                    if (title.Length > 180) title = title.Substring(0, 180) + "…";
                    await svc.CreateAsync(new CreateSystemAnnouncementDto
                    {
                        Title = title,
                        Content = $"Cửa hàng \"{s.Name}\" có license sẽ hết hạn vào {s.ExpiryDate:dd/MM/yyyy}. Vui lòng liên hệ đại lý / nhà cung cấp để gia hạn.\n\n{marker}",
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
                        // Hiển thị banner đến hết ngày hết hạn (UTC date + 1 ngày)
                        ExpiresAt = s.ExpiryDate?.Date.AddDays(1)
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

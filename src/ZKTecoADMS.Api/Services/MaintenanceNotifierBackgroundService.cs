using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.DTOs.SystemAdmin;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Phát thông báo trước khi vào cửa sổ bảo trì N phút (theo NotifyBeforeMinutesCsv).
/// Cũng phát "đang bảo trì" khi bắt đầu và "hoàn tất" khi kết thúc.
/// Chạy mỗi 60s.
/// </summary>
public class MaintenanceNotifierBackgroundService : BackgroundService
{
    private readonly IServiceProvider _sp;
    private readonly ILogger<MaintenanceNotifierBackgroundService> _logger;
    private readonly TimeSpan _interval = TimeSpan.FromSeconds(60);

    public MaintenanceNotifierBackgroundService(IServiceProvider sp, ILogger<MaintenanceNotifierBackgroundService> logger)
    {
        _sp = sp; _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("🔧 MaintenanceNotifier service started");
        await Task.Delay(TimeSpan.FromSeconds(45), stoppingToken);
        while (!stoppingToken.IsCancellationRequested)
        {
            try { await RunOnceAsync(stoppingToken); }
            catch (Exception ex) { _logger.LogError(ex, "MaintenanceNotifier run failed"); }
            await Task.Delay(_interval, stoppingToken);
        }
    }

    private async Task RunOnceAsync(CancellationToken ct)
    {
        using var scope = _sp.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<ZKTecoDbContext>();
        var svc = scope.ServiceProvider.GetRequiredService<IAnnouncementService>();
        var now = DateTime.UtcNow;

        var horizon = now.AddHours(24);
        var windows = await db.MaintenanceWindows
            .Where(w => w.IsActive && w.EndAt > now.AddMinutes(-10) && w.StartAt <= horizon)
            .ToListAsync(ct);

        foreach (var w in windows)
        {
            // Pre-notice
            if (w.StartAt > now)
            {
                var minutesLeft = (int)(w.StartAt - now).TotalMinutes;
                var thresholds = ParseCsv(w.NotifyBeforeMinutesCsv ?? "60,15,5");
                var notified = ParseCsv(w.NotifiedMinutesCsv);
                foreach (var t in thresholds.OrderByDescending(x => x))
                {
                    if (minutesLeft <= t && minutesLeft > Math.Max(0, t - 2) && !notified.Contains(t))
                    {
                        await SendPreNotice(svc, w, t, ct);
                        notified.Add(t);
                        w.NotifiedMinutesCsv = string.Join(',', notified.Distinct().OrderByDescending(x => x));
                    }
                }
            }

            // Start notice
            if (!w.StartNotified && w.StartAt <= now && w.EndAt > now)
            {
                await SendStartNotice(svc, w, ct);
                w.StartNotified = true;
            }

            // End notice
            if (!w.EndNotified && w.EndAt <= now)
            {
                await SendEndNotice(svc, w, ct);
                w.EndNotified = true;
                w.IsActive = false;
            }
        }
        await db.SaveChangesAsync(ct);
    }

    private static Task SendPreNotice(IAnnouncementService svc, Domain.Entities.MaintenanceWindow w, int minutes, CancellationToken ct)
        => svc.CreateAsync(new CreateSystemAnnouncementDto
        {
            Title = $"🔧 Sắp bảo trì: {w.Title} (sau {minutes} phút)",
            Content = $"{w.Message}\n\nThời gian: {w.StartAt:dd/MM/yyyy HH:mm} → {w.EndAt:dd/MM/yyyy HH:mm} (UTC).",
            Kind = AnnouncementKind.Maintenance,
            Severity = minutes <= 5 ? AnnouncementSeverity.Critical : AnnouncementSeverity.Warning,
            Channels = NotificationChannel.InApp | NotificationChannel.Banner,
            RequireAck = false,
            AllowDismiss = true,
            Audience = new AudienceSpec { AllUsers = true },
            SendNow = true,
            ExpiresAt = w.StartAt
        }, Guid.Empty, ct);

    private static Task SendStartNotice(IAnnouncementService svc, Domain.Entities.MaintenanceWindow w, CancellationToken ct)
        => svc.CreateAsync(new CreateSystemAnnouncementDto
        {
            Title = $"🛠️ Đang bảo trì: {w.Title}",
            Content = $"{w.Message}\n\nDự kiến hoàn tất: {w.EndAt:dd/MM/yyyy HH:mm}.",
            Kind = AnnouncementKind.Maintenance,
            Severity = AnnouncementSeverity.Critical,
            Channels = NotificationChannel.InApp | NotificationChannel.Banner,
            RequireAck = false,
            AllowDismiss = false,
            Audience = new AudienceSpec { AllUsers = true },
            SendNow = true,
            ExpiresAt = w.EndAt
        }, Guid.Empty, ct);

    private static Task SendEndNotice(IAnnouncementService svc, Domain.Entities.MaintenanceWindow w, CancellationToken ct)
        => svc.CreateAsync(new CreateSystemAnnouncementDto
        {
            Title = $"✅ Bảo trì hoàn tất: {w.Title}",
            Content = "Hệ thống đã hoạt động trở lại bình thường. Cảm ơn bạn đã kiên nhẫn chờ đợi.",
            Kind = AnnouncementKind.Maintenance,
            Severity = AnnouncementSeverity.Success,
            Channels = NotificationChannel.InApp | NotificationChannel.Banner,
            RequireAck = false,
            AllowDismiss = true,
            Audience = new AudienceSpec { AllUsers = true },
            SendNow = true,
            ExpiresAt = DateTime.UtcNow.AddHours(2)
        }, Guid.Empty, ct);

    private static List<int> ParseCsv(string? csv)
    {
        var list = new List<int>();
        if (string.IsNullOrWhiteSpace(csv)) return list;
        foreach (var p in csv.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
            if (int.TryParse(p, out var v)) list.Add(v);
        return list;
    }
}

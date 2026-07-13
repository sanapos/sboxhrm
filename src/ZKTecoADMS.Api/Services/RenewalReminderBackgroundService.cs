using Microsoft.EntityFrameworkCore;
using Microsoft.AspNetCore.Identity;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Application.DTOs.SystemAdmin;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
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
    private static readonly int[] Thresholds = { 30, 15, 7, 3, 1, 0 };

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
        var renewalNotify = scope.ServiceProvider.GetRequiredService<IRenewalNotificationService>();
        var notificationService = scope.ServiceProvider.GetRequiredService<ISystemNotificationService>();
        var userManager = scope.ServiceProvider.GetRequiredService<UserManager<ApplicationUser>>();
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
                var marker = RenewalNotificationHelper.BuildMarker(d, s.Id);
                var since = DateTime.UtcNow.AddHours(-23);
                var dup = await db.SystemAnnouncements.AsNoTracking()
                    .AnyAsync(a => a.CreatedAt >= since && (a.Title.Contains(marker) || a.Content.Contains(marker)), ct);
                if (dup) continue;

                try
                {
                    await renewalNotify.DismissPendingRenewalAnnouncementsAsync(s.Id, ct);

                    // Title: ngắn gọn, không kèm marker. Frontend sẽ tự tính lại số ngày từ ExpiresAt.
                    var title = d == 0
                        ? $"⏰ {s.Name}: license hết hạn hôm nay"
                        : $"⏰ {s.Name}: license sắp hết hạn ({d} ngày)";
                    if (title.Length > 180) title = title.Substring(0, 180) + "…";
                    await svc.CreateAsync(new CreateSystemAnnouncementDto
                    {
                        Title = title,
                        Content = $"Cửa hàng \"{s.Name}\" có license sẽ hết hạn vào {s.ExpiryDate:dd/MM/yyyy}. Vui lòng liên hệ đại lý / nhà cung cấp để gia hạn.\n\n{marker}",
                        Kind = AnnouncementKind.Renewal,
                        Severity = d <= 3 ? AnnouncementSeverity.Critical : AnnouncementSeverity.Warning,
                        Channels = NotificationChannel.InApp | NotificationChannel.Banner,
                        RequireAck = d == 0,
                        AllowDismiss = d != 0,
                        Audience = new AudienceSpec
                        {
                            AllUsers = false,
                            StoreIds = new List<Guid> { s.Id }
                        },
                        SendNow = true,
                        // T-0: giữ banner 14 ngày sau hết hạn; trước đó đến ExpiryDate+1
                        ExpiresAt = d == 0
                            ? s.ExpiryDate?.Date.AddDays(14)
                            : s.ExpiryDate?.Date.AddDays(1)
                    }, Guid.Empty, ct);
                    _logger.LogInformation("Sent renewal reminder T-{D} for store {Store}", d, s.Name);

                    var adminTitle = d == 0
                        ? $"⏰ {s.Name}: license hết hạn hôm nay"
                        : $"⏰ {s.Name}: sắp hết hạn license ({d} ngày)";
                    var adminMessage = d == 0
                        ? $"Cửa hàng \"{s.Name}\" hết hạn license hôm nay. Vui lòng liên hệ gia hạn."
                        : $"Cửa hàng \"{s.Name}\" sẽ hết hạn license vào {s.ExpiryDate:dd/MM/yyyy} (còn {d} ngày).";
                    await SuperAdminNotificationHelper.NotifySuperAdminsAsync(
                        notificationService,
                        userManager,
                        d <= 3 ? NotificationType.Warning : NotificationType.Info,
                        adminTitle,
                        adminMessage,
                        relatedUrl: SuperAdminNotificationHelper.AdminStoresUrl,
                        relatedEntityId: s.Id,
                        relatedEntityType: "Store",
                        categoryCode: "renewal",
                        storeId: s.Id);
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Failed renewal reminder T-{D} store {Store}", d, s.Id);
                }
            }
        }
    }
}

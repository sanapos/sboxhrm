using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Services;

/// <summary>Mỗi phút: đăng các bài truyền thông hẹn giờ đã đến giờ và thông báo cho đối tượng nhận.</summary>
public class CommScheduleBackgroundService(IServiceProvider sp, ILogger<CommScheduleBackgroundService> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        await Task.Delay(TimeSpan.FromSeconds(40), stoppingToken);
        while (!stoppingToken.IsCancellationRequested)
        {
            try { await RunOnceAsync(stoppingToken); }
            catch (Exception ex) { logger.LogError(ex, "Comm schedule run failed"); }
            await Task.Delay(TimeSpan.FromMinutes(1), stoppingToken);
        }
    }

    public static async Task<int> PublishDueAsync(ZKTecoDbContext db, ISystemNotificationService? notify, DateTime nowUtc, CancellationToken ct)
    {
        var due = await db.InternalCommunications.IgnoreQueryFilters().AsTracking()
            .Where(p => p.Status == CommunicationStatus.Scheduled && p.ScheduledAt != null && p.ScheduledAt <= nowUtc)
            .OrderBy(p => p.ScheduledAt)
            .Take(50)
            .ToListAsync(ct);
        foreach (var p in due)
        {
            p.Status = CommunicationStatus.Published;
            p.PublishedAt = nowUtc;
        }
        if (due.Count == 0) return 0;
        await db.SaveChangesAsync(ct);
        if (notify == null) return due.Count;
        foreach (var p in due)
        {
            try
            {
                var ch = p.ChannelId.HasValue
                    ? await db.CommChannels.IgnoreQueryFilters().AsNoTracking().FirstOrDefaultAsync(c => c.Id == p.ChannelId, ct)
                    : null;
                var people = await CommV2Helper.AudienceEmployeesAsync(db, p.StoreId, CommV2Helper.Audience(p.Audience), ch, ct);
                var ids = people.Where(x => x.UserId.HasValue && x.UserId != p.AuthorId).Select(x => x.UserId!.Value).Distinct().ToList();
                if (ids.Count > 0)
                    await notify.CreateAndSendToUsersAsync(ids,
                        p.RequireAck ? NotificationType.Warning : NotificationType.Info,
                        p.RequireAck ? "Văn bản mới — bắt buộc đọc" : $"{ch?.Name ?? "Truyền thông"}: bài mới",
                        p.Title, relatedEntityId: p.Id, relatedEntityType: "Communication", fromUserId: p.AuthorId,
                        categoryCode: "communication", storeId: p.StoreId);
            }
            catch (Exception) { /* thông báo lỗi không chặn */ }
        }
        return due.Count;
    }

    private async Task RunOnceAsync(CancellationToken ct)
    {
        using var scope = sp.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<ZKTecoDbContext>();
        var notify = scope.ServiceProvider.GetService<ISystemNotificationService>();
        var n = await PublishDueAsync(db, notify, DateTime.UtcNow, ct);
        if (n > 0) logger.LogInformation("Published {N} scheduled communications", n);
    }
}

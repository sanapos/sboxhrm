using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Infrastructure.Services;

public class RenewalNotificationService : IRenewalNotificationService
{
    private readonly ZKTecoDbContext _db;
    private readonly ISystemNotificationService _notify;
    private readonly ILogger<RenewalNotificationService> _logger;

    public RenewalNotificationService(
        ZKTecoDbContext db,
        ISystemNotificationService notify,
        ILogger<RenewalNotificationService> logger)
    {
        _db = db;
        _notify = notify;
        _logger = logger;
    }

    public async Task InvalidateForStoreAsync(
        Guid storeId,
        string storeName,
        DateTime? newExpiryDate,
        bool sendSuccessNotification,
        CancellationToken ct = default)
    {
        var now = DateTime.UtcNow;
        var needle = RenewalNotificationHelper.StoreContentNeedle(storeId);

        var renewalAnnouncementIds = await _db.SystemAnnouncements
            .AsNoTracking()
            .Where(a => a.Kind == AnnouncementKind.Renewal
                && a.Status == AnnouncementStatus.Sent
                && a.Content.Contains(needle))
            .Select(a => a.Id)
            .ToListAsync(ct);

        if (renewalAnnouncementIds.Count > 0)
        {
            await _db.SystemAnnouncements
                .Where(a => renewalAnnouncementIds.Contains(a.Id))
                .ExecuteUpdateAsync(p => p
                    .SetProperty(a => a.Status, AnnouncementStatus.Cancelled)
                    .SetProperty(a => a.ExpiresAt, now), ct);

            await _db.AnnouncementDeliveries
                .Where(d => renewalAnnouncementIds.Contains(d.AnnouncementId)
                    && d.DismissedAt == null)
                .ExecuteUpdateAsync(p => p.SetProperty(d => d.DismissedAt, now), ct);
        }

        await _db.Notifications
            .Where(n => n.StoreId == storeId
                && !n.IsRead
                && (n.CategoryCode == "renewal" || n.CategoryCode == "RENEWAL"
                    || (n.RelatedEntityType == nameof(SystemAnnouncement)
                        && n.RelatedEntityId != null
                        && renewalAnnouncementIds.Contains(n.RelatedEntityId.Value))))
            .ExecuteUpdateAsync(p => p
                .SetProperty(n => n.IsRead, true)
                .SetProperty(n => n.ReadAt, now), ct);

        _logger.LogInformation(
            "Invalidated renewal alerts for store {StoreId}: {AnnouncementCount} announcements",
            storeId, renewalAnnouncementIds.Count);

        if (!sendSuccessNotification || newExpiryDate == null) return;

        var userIds = await _db.Users.AsNoTracking()
            .Where(u => u.IsActive && u.StoreId == storeId)
            .Select(u => u.Id)
            .ToListAsync(ct);

        if (userIds.Count == 0) return;

        var expiryLocal = newExpiryDate.Value.ToLocalTime();
        await _notify.CreateAndSendToUsersAsync(
            targetUserIds: userIds,
            type: NotificationType.Success,
            title: "Gia hạn license thành công",
            message: $"Cửa hàng \"{storeName}\" đã được gia hạn. License có hiệu lực đến {expiryLocal:dd/MM/yyyy}.",
            relatedEntityId: storeId,
            relatedEntityType: "Store",
            categoryCode: "license",
            storeId: storeId);
    }

    public async Task DismissPendingRenewalAnnouncementsAsync(Guid storeId, CancellationToken ct = default)
    {
        var now = DateTime.UtcNow;
        var needle = RenewalNotificationHelper.StoreContentNeedle(storeId);

        var ids = await _db.SystemAnnouncements
            .AsNoTracking()
            .Where(a => a.Kind == AnnouncementKind.Renewal
                && a.Status == AnnouncementStatus.Sent
                && (a.ExpiresAt == null || a.ExpiresAt > now)
                && a.Content.Contains(needle))
            .Select(a => a.Id)
            .ToListAsync(ct);

        if (ids.Count == 0) return;

        await _db.SystemAnnouncements
            .Where(a => ids.Contains(a.Id))
            .ExecuteUpdateAsync(p => p
                .SetProperty(a => a.Status, AnnouncementStatus.Cancelled)
                .SetProperty(a => a.ExpiresAt, now), ct);

        await _db.AnnouncementDeliveries
            .Where(d => ids.Contains(d.AnnouncementId) && d.DismissedAt == null)
            .ExecuteUpdateAsync(p => p.SetProperty(d => d.DismissedAt, now), ct);
    }

    public async Task CleanupStaleRenewalAlertsAsync(CancellationToken ct = default)
    {
        var now = DateTime.UtcNow;
        var today = now.Date;
        var suppressAfter = today.AddDays(RenewalNotificationHelper.ReminderThresholdMaxDays);

        var activeStores = await _db.Stores.AsNoTracking()
            .IgnoreQueryFilters()
            .Where(s => s.ExpiryDate != null && s.ExpiryDate.Value.Date > suppressAfter)
            .Select(s => new { s.Id, s.Name, s.ExpiryDate })
            .ToListAsync(ct);

        foreach (var store in activeStores)
        {
            await InvalidateForStoreAsync(
                store.Id,
                store.Name,
                store.ExpiryDate,
                sendSuccessNotification: false,
                ct);
        }

        if (activeStores.Count > 0)
        {
            _logger.LogInformation(
                "Stale renewal cleanup: cleared alerts for {Count} stores with expiry beyond T+{Days}",
                activeStores.Count, RenewalNotificationHelper.ReminderThresholdMaxDays);
        }
    }
}

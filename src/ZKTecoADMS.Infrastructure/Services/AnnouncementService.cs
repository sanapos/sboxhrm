using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using ZKTecoADMS.Application.DTOs.SystemAdmin;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Infrastructure.Services;

public class AnnouncementService : IAnnouncementService
{
    private static readonly JsonSerializerOptions Json = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        DefaultIgnoreCondition = System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingNull
    };

    private readonly ZKTecoDbContext _db;
    private readonly IAudienceResolver _audience;
    private readonly ISystemNotificationService _notify;
    private readonly IEnumerable<INotificationChannelProvider> _channelProviders;
    private readonly ILogger<AnnouncementService> _logger;

    public AnnouncementService(
        ZKTecoDbContext db,
        IAudienceResolver audience,
        ISystemNotificationService notify,
        IEnumerable<INotificationChannelProvider> channelProviders,
        ILogger<AnnouncementService> logger)
    {
        _db = db;
        _audience = audience;
        _notify = notify;
        _channelProviders = channelProviders;
        _logger = logger;
    }

    public async Task<SystemAnnouncementDto> CreateAsync(CreateSystemAnnouncementDto request, Guid actorUserId, CancellationToken ct = default)
    {
        var entity = new SystemAnnouncement
        {
            Id = Guid.NewGuid(),
            Title = request.Title,
            Content = request.Content,
            Kind = request.Kind,
            Severity = request.Severity,
            Channels = request.Channels == 0 ? NotificationChannel.InApp : request.Channels,
            AudienceJson = JsonSerializer.Serialize(request.Audience ?? new AudienceSpec { AllUsers = true }, Json),
            ScheduleAt = request.ScheduleAt,
            ExpiresAt = request.ExpiresAt,
            RequireAck = request.RequireAck,
            AllowDismiss = request.AllowDismiss,
            ImageUrl = request.ImageUrl,
            ActionUrl = request.ActionUrl,
            ActionLabel = request.ActionLabel,
            CreatedAt = DateTime.UtcNow,
            CreatedBy = actorUserId.ToString(),
            Status = AnnouncementStatus.Draft
        };

        if (request.SendNow && !request.ScheduleAt.HasValue)
        {
            entity.Status = AnnouncementStatus.Sending;
        }
        else if (request.ScheduleAt.HasValue && request.ScheduleAt.Value > DateTime.UtcNow)
        {
            entity.Status = AnnouncementStatus.Scheduled;
        }

        _db.SystemAnnouncements.Add(entity);
        await _db.SaveChangesAsync(ct);

        if (entity.Status == AnnouncementStatus.Sending)
        {
            await SendInternalAsync(entity, ct);
        }

        return MapToDto(entity);
    }

    public async Task<SystemAnnouncementDto?> GetAsync(Guid id, CancellationToken ct = default)
    {
        var ent = await _db.SystemAnnouncements.AsNoTracking().FirstOrDefaultAsync(x => x.Id == id, ct);
        return ent == null ? null : MapToDto(ent);
    }

    public async Task<List<SystemAnnouncementDto>> ListAsync(int page, int pageSize, string? keyword, int? kind, int? status, CancellationToken ct = default)
    {
        var q = _db.SystemAnnouncements.AsNoTracking().AsQueryable();
        if (!string.IsNullOrWhiteSpace(keyword))
        {
            var kw = $"%{keyword.Trim()}%";
            q = q.Where(x => EF.Functions.ILike(x.Title, kw) || EF.Functions.ILike(x.Content, kw));
        }
        if (kind.HasValue) q = q.Where(x => (int)x.Kind == kind.Value);
        if (status.HasValue) q = q.Where(x => (int)x.Status == status.Value);

        var items = await q
            .OrderByDescending(x => x.CreatedAt)
            .Skip(Math.Max(0, (page - 1)) * pageSize)
            .Take(Math.Max(1, Math.Min(pageSize, 200)))
            .ToListAsync(ct);

        return items.Select(MapToDto).ToList();
    }

    public async Task<bool> CancelAsync(Guid id, CancellationToken ct = default)
    {
        var ent = await _db.SystemAnnouncements.FirstOrDefaultAsync(x => x.Id == id, ct);
        if (ent == null) return false;
        ent.Status = AnnouncementStatus.Cancelled;
        await _db.SaveChangesAsync(ct);
        return true;
    }

    public async Task<bool> DeleteAsync(Guid id, CancellationToken ct = default)
    {
        var ent = await _db.SystemAnnouncements.FirstOrDefaultAsync(x => x.Id == id, ct);
        if (ent == null) return false;
        _db.SystemAnnouncements.Remove(ent);
        await _db.SaveChangesAsync(ct);
        return true;
    }

    public async Task<int> SendAsync(Guid id, CancellationToken ct = default)
    {
        var ent = await _db.SystemAnnouncements.FirstOrDefaultAsync(x => x.Id == id, ct);
        if (ent == null) return 0;
        if (ent.Status == AnnouncementStatus.Sent || ent.Status == AnnouncementStatus.Cancelled) return 0;
        ent.Status = AnnouncementStatus.Sending;
        await _db.SaveChangesAsync(ct);
        return await SendInternalAsync(ent, ct);
    }

    public async Task<int> ResendFailedAsync(Guid id, CancellationToken ct = default)
    {
        var failed = await _db.AnnouncementDeliveries
            .Where(x => x.AnnouncementId == id && (x.Status == DeliveryStatus.Failed || x.Status == DeliveryStatus.Pending))
            .ToListAsync(ct);
        if (failed.Count == 0) return 0;

        var ann = await _db.SystemAnnouncements.FirstOrDefaultAsync(x => x.Id == id, ct);
        if (ann == null) return 0;

        var count = 0;
        foreach (var d in failed)
        {
            try
            {
                await _notify.CreateAndSendAsync(
                    targetUserId: d.UserId,
                    type: MapKindToNotificationType(ann.Kind),
                    title: ann.Title,
                    message: ann.Content,
                    relatedUrl: ann.ActionUrl,
                    relatedEntityId: ann.Id,
                    relatedEntityType: nameof(SystemAnnouncement),
                    categoryCode: ann.Kind.ToString().ToUpperInvariant(),
                    storeId: d.StoreId);

                d.Status = DeliveryStatus.Delivered;
                d.DeliveredAt = DateTime.UtcNow;
                d.ErrorMessage = null;
                count++;
            }
            catch (Exception ex)
            {
                d.Status = DeliveryStatus.Failed;
                d.ErrorMessage = ex.Message[..Math.Min(ex.Message.Length, 500)];
                _logger.LogWarning(ex, "Resend delivery failed for user {UserId}", d.UserId);
            }
        }
        ann.DeliveredCount = await _db.AnnouncementDeliveries
            .CountAsync(x => x.AnnouncementId == id && x.Status == DeliveryStatus.Delivered, ct);
        await _db.SaveChangesAsync(ct);
        return count;
    }

    public async Task<AnnouncementStatsDto> GetStatsAsync(Guid id, CancellationToken ct = default)
    {
        var ann = await _db.SystemAnnouncements.AsNoTracking().FirstOrDefaultAsync(x => x.Id == id, ct);
        var deliveries = await _db.AnnouncementDeliveries.AsNoTracking()
            .Where(x => x.AnnouncementId == id)
            .ToListAsync(ct);

        return new AnnouncementStatsDto
        {
            AnnouncementId = id,
            Recipients = ann?.RecipientCount ?? deliveries.Count,
            Delivered = deliveries.Count(d => d.Status == DeliveryStatus.Delivered),
            Seen = deliveries.Count(d => d.SeenAt.HasValue),
            Clicked = deliveries.Count(d => d.ClickedAt.HasValue),
            Acked = deliveries.Count(d => d.AckedAt.HasValue),
            Dismissed = deliveries.Count(d => d.DismissedAt.HasValue),
            Failed = deliveries.Count(d => d.Status == DeliveryStatus.Failed),
            ByChannel = deliveries.GroupBy(d => d.Channel.ToString()).ToDictionary(g => g.Key, g => g.Count())
        };
    }

    public async Task<List<ActiveAnnouncementDto>> GetActiveForUserAsync(Guid userId, CancellationToken ct = default)
    {
        var now = DateTime.UtcNow;
        const int bannerFlag = (int)NotificationChannel.Banner;
        const int inAppFlag = (int)NotificationChannel.InApp;
        var rows = await (
            from d in _db.AnnouncementDeliveries
            join a in _db.SystemAnnouncements on d.AnnouncementId equals a.Id
            where d.UserId == userId
                && a.Status == AnnouncementStatus.Sent
                && (a.ExpiresAt == null || a.ExpiresAt > now)
                && d.DismissedAt == null
                && (((int)a.Channels & bannerFlag) != 0 || a.RequireAck)
                && (
                    (((int)a.Channels & bannerFlag) != 0 && d.Channel == NotificationChannel.Banner)
                    || (((int)a.Channels & bannerFlag) == 0 && ((int)a.Channels & inAppFlag) != 0 && d.Channel == NotificationChannel.InApp)
                    || (a.RequireAck && d.Channel == NotificationChannel.InApp)
                )
            orderby a.Severity descending, a.CreatedAt descending
            select new ActiveAnnouncementDto
            {
                Id = a.Id,
                Title = a.Title,
                Content = a.Content,
                Kind = a.Kind,
                Severity = a.Severity,
                RequireAck = a.RequireAck,
                AllowDismiss = a.AllowDismiss,
                ImageUrl = a.ImageUrl,
                ActionUrl = a.ActionUrl,
                ActionLabel = a.ActionLabel,
                ExpiresAt = a.ExpiresAt,
                IsSeen = d.SeenAt != null,
                IsAcked = d.AckedAt != null,
                IsDismissed = d.DismissedAt != null
            }).Take(20).ToListAsync(ct);

        var active = rows.Where(r => !r.IsAcked).ToList();
        return await EnrichAndFilterRenewalAsync(active, ct);
    }

    /// <summary>
    /// Gắn expiry live từ Store, ẩn renewal đã gia hạn xa, giữ tối đa 1 renewal/store.
    /// </summary>
    private async Task<List<ActiveAnnouncementDto>> EnrichAndFilterRenewalAsync(
        List<ActiveAnnouncementDto> items,
        CancellationToken ct)
    {
        if (items.Count == 0) return items;

        var renewalStoreIds = items
            .Where(i => i.Kind == AnnouncementKind.Renewal)
            .Select(i => RenewalNotificationHelper.TryParseStoreId(i.Content, out var sid) ? sid : Guid.Empty)
            .Where(id => id != Guid.Empty)
            .Distinct()
            .ToList();

        var expiryByStore = renewalStoreIds.Count == 0
            ? new Dictionary<Guid, DateTime?>()
            : await _db.Stores.AsNoTracking()
                .IgnoreQueryFilters()
                .Where(s => renewalStoreIds.Contains(s.Id))
                .ToDictionaryAsync(s => s.Id, s => s.ExpiryDate, ct);

        var now = DateTime.UtcNow;
        var enriched = new List<ActiveAnnouncementDto>();

        foreach (var item in items)
        {
            if (item.Kind != AnnouncementKind.Renewal)
            {
                enriched.Add(item);
                continue;
            }

            if (!RenewalNotificationHelper.TryParseStoreId(item.Content, out var storeId))
            {
                enriched.Add(item);
                continue;
            }

            expiryByStore.TryGetValue(storeId, out var liveExpiry);
            var daysLeft = RenewalNotificationHelper.ComputeDaysLeft(liveExpiry, now);

            if (RenewalNotificationHelper.ShouldSuppressRenewalAlert(liveExpiry, now))
                continue;

            item.RelatedStoreId = storeId;
            item.LiveExpiryDate = liveExpiry;
            item.LiveDaysLeft = daysLeft;
            enriched.Add(item);
        }

        var nonRenewal = enriched.Where(i => i.Kind != AnnouncementKind.Renewal).ToList();
        var renewals = enriched
            .Where(i => i.Kind == AnnouncementKind.Renewal)
            .GroupBy(i => i.RelatedStoreId)
            .Select(g => g.OrderBy(i => i.LiveDaysLeft ?? int.MaxValue)
                .ThenByDescending(i => (int)i.Severity)
                .First())
            .ToList();

        return nonRenewal.Concat(renewals)
            .OrderByDescending(i => (int)i.Severity)
            .ThenByDescending(i => i.ExpiresAt)
            .Take(20)
            .ToList();
    }

    public async Task MarkSeenAsync(Guid announcementId, Guid userId, CancellationToken ct = default)
    {
        var d = await _db.AnnouncementDeliveries.FirstOrDefaultAsync(x => x.AnnouncementId == announcementId && x.UserId == userId, ct);
        if (d == null || d.SeenAt.HasValue) return;
        d.SeenAt = DateTime.UtcNow;
        await _db.SystemAnnouncements.Where(a => a.Id == announcementId).ExecuteUpdateAsync(p => p.SetProperty(a => a.SeenCount, a => a.SeenCount + 1), ct);
        await _db.SaveChangesAsync(ct);
    }

    public async Task MarkClickedAsync(Guid announcementId, Guid userId, CancellationToken ct = default)
    {
        var d = await _db.AnnouncementDeliveries.FirstOrDefaultAsync(x => x.AnnouncementId == announcementId && x.UserId == userId, ct);
        if (d == null || d.ClickedAt.HasValue) return;
        d.ClickedAt = DateTime.UtcNow;
        await _db.SystemAnnouncements.Where(a => a.Id == announcementId).ExecuteUpdateAsync(p => p.SetProperty(a => a.ClickedCount, a => a.ClickedCount + 1), ct);
        await _db.SaveChangesAsync(ct);
    }

    public async Task MarkAckedAsync(Guid announcementId, Guid userId, CancellationToken ct = default)
    {
        var d = await _db.AnnouncementDeliveries.FirstOrDefaultAsync(x => x.AnnouncementId == announcementId && x.UserId == userId, ct);
        if (d == null || d.AckedAt.HasValue) return;
        d.AckedAt = DateTime.UtcNow;
        await _db.SystemAnnouncements.Where(a => a.Id == announcementId).ExecuteUpdateAsync(p => p.SetProperty(a => a.AckedCount, a => a.AckedCount + 1), ct);
        await _db.SaveChangesAsync(ct);
    }

    public async Task MarkDismissedAsync(Guid announcementId, Guid userId, CancellationToken ct = default)
    {
        var d = await _db.AnnouncementDeliveries.FirstOrDefaultAsync(x => x.AnnouncementId == announcementId && x.UserId == userId, ct);
        if (d == null || d.DismissedAt.HasValue) return;
        d.DismissedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync(ct);
    }

    // ---------------- helpers ----------------

    private async Task<int> SendInternalAsync(SystemAnnouncement entity, CancellationToken ct)
    {
        var spec = string.IsNullOrEmpty(entity.AudienceJson)
            ? new AudienceSpec { AllUsers = true }
            : (JsonSerializer.Deserialize<AudienceSpec>(entity.AudienceJson, Json) ?? new AudienceSpec { AllUsers = true });

        var members = await _audience.ResolveAsync(spec, ct);
        entity.RecipientCount = members.Count;

        if (members.Count == 0)
        {
            entity.Status = AnnouncementStatus.Sent;
            entity.SentAt = DateTime.UtcNow;
            await _db.SaveChangesAsync(ct);
            return 0;
        }

        // Avoid duplicating deliveries on resend
        var existing = await _db.AnnouncementDeliveries
            .Where(d => d.AnnouncementId == entity.Id)
            .Select(d => new { d.UserId, d.Channel })
            .ToListAsync(ct);
        var existingSet = existing.Select(e => (e.UserId, e.Channel)).ToHashSet();

        var channels = ExpandChannels(entity.Channels);
        var notifType = MapKindToNotificationType(entity.Kind);
        var category = entity.Kind.ToString().ToUpperInvariant();

        var batchToCreate = new List<AnnouncementDelivery>();
        foreach (var m in members)
        {
            foreach (var ch in channels)
            {
                if (existingSet.Contains((m.UserId, ch))) continue;
                batchToCreate.Add(new AnnouncementDelivery
                {
                    Id = Guid.NewGuid(),
                    AnnouncementId = entity.Id,
                    UserId = m.UserId,
                    StoreId = m.StoreId,
                    Channel = ch,
                    Status = DeliveryStatus.Pending,
                    CreatedAt = DateTime.UtcNow
                });
            }
        }
        if (batchToCreate.Count > 0)
        {
            _db.AnnouncementDeliveries.AddRange(batchToCreate);
            await _db.SaveChangesAsync(ct);
        }

        // Send InApp/Banner via existing notification service (DB row + SignalR push)
        var inAppMembers = members.Select(m => m.UserId).Distinct().ToList();
        if (entity.Channels.HasFlag(NotificationChannel.InApp) || entity.Channels.HasFlag(NotificationChannel.Banner))
        {
            await _notify.CreateAndSendToUsersAsync(
                targetUserIds: inAppMembers,
                type: notifType,
                title: entity.Title,
                message: entity.Content,
                relatedUrl: entity.ActionUrl,
                relatedEntityId: entity.Id,
                relatedEntityType: nameof(SystemAnnouncement),
                categoryCode: category);

            // Mark deliveries as Delivered for InApp/Banner channels
            var inAppChannels = new[] { NotificationChannel.InApp, NotificationChannel.Banner };
            await _db.AnnouncementDeliveries
                .Where(d => d.AnnouncementId == entity.Id && inAppChannels.Contains(d.Channel))
                .ExecuteUpdateAsync(p => p
                    .SetProperty(d => d.Status, DeliveryStatus.Delivered)
                    .SetProperty(d => d.DeliveredAt, DateTime.UtcNow), ct);
        }

        // Other channels (Email/Sms/Push) — Phase 3: gọi provider thật.
        var providerChannels = new[] { NotificationChannel.Email, NotificationChannel.Sms, NotificationChannel.Push };
        var requestedExternal = providerChannels.Where(c => entity.Channels.HasFlag(c)).ToList();
        if (requestedExternal.Count > 0)
        {
            // Load contact info for all members in 1 query
            var memberIds = members.Select(m => m.UserId).ToList();
            var contacts = await _db.Users.AsNoTracking()
                .Where(u => memberIds.Contains(u.Id))
                .Select(u => new { u.Id, u.Email, u.PhoneNumber, u.FirstName, u.LastName })
                .ToListAsync(ct);
            var contactMap = contacts.ToDictionary(x => x.Id);

            foreach (var ch in requestedExternal)
            {
                var provider = _channelProviders.FirstOrDefault(p => p.Channel == ch);
                var pendingDeliveries = await _db.AnnouncementDeliveries
                    .Where(d => d.AnnouncementId == entity.Id && d.Channel == ch && d.Status == DeliveryStatus.Pending)
                    .ToListAsync(ct);

                if (provider == null || !provider.IsConfigured)
                {
                    foreach (var d in pendingDeliveries)
                    {
                        d.Status = DeliveryStatus.Skipped;
                        d.ErrorMessage = $"Provider for {ch} not configured";
                    }
                    await _db.SaveChangesAsync(ct);
                    continue;
                }

                foreach (var d in pendingDeliveries)
                {
                    contactMap.TryGetValue(d.UserId, out var c);
                    var recipient = new ChannelRecipient(
                        UserId: d.UserId,
                        Email: c?.Email,
                        Phone: c?.PhoneNumber,
                        FcmToken: null,
                        DisplayName: c == null ? string.Empty : $"{c.LastName} {c.FirstName}".Trim(),
                        StoreId: d.StoreId);
                    var result = await provider.SendAsync(recipient, entity.Title, entity.Content, entity.ActionUrl, ct);
                    if (result.Success)
                    {
                        d.Status = DeliveryStatus.Delivered;
                        d.DeliveredAt = DateTime.UtcNow;
                    }
                    else
                    {
                        d.Status = DeliveryStatus.Failed;
                        var msg = result.ErrorMessage ?? "Unknown error";
                        d.ErrorMessage = msg[..Math.Min(msg.Length, 500)];
                    }
                }
                await _db.SaveChangesAsync(ct);
            }
        }

        var deliveredCount = await _db.AnnouncementDeliveries
            .CountAsync(d => d.AnnouncementId == entity.Id && d.Status == DeliveryStatus.Delivered, ct);

        entity.DeliveredCount = deliveredCount;
        entity.Status = AnnouncementStatus.Sent;
        entity.SentAt = DateTime.UtcNow;
        await _db.SaveChangesAsync(ct);

        _logger.LogInformation("📣 Announcement {Id} sent: {Recipients} recipients, {Delivered} delivered",
            entity.Id, entity.RecipientCount, deliveredCount);

        return deliveredCount;
    }

    private static List<NotificationChannel> ExpandChannels(NotificationChannel mask)
    {
        var list = new List<NotificationChannel>();
        foreach (var ch in new[] {
            NotificationChannel.InApp, NotificationChannel.Banner,
            NotificationChannel.Email, NotificationChannel.Sms, NotificationChannel.Push })
        {
            if (mask.HasFlag(ch)) list.Add(ch);
        }
        return list.Count == 0 ? new List<NotificationChannel> { NotificationChannel.InApp } : list;
    }

    private static NotificationType MapKindToNotificationType(AnnouncementKind kind) => kind switch
    {
        AnnouncementKind.Maintenance => NotificationType.Maintenance,
        AnnouncementKind.Upgrade => NotificationType.Upgrade,
        AnnouncementKind.Renewal => NotificationType.Renewal,
        AnnouncementKind.Marketing => NotificationType.Marketing,
        _ => NotificationType.Announcement
    };

    private static SystemAnnouncementDto MapToDto(SystemAnnouncement e)
    {
        AudienceSpec audience;
        try
        {
            audience = string.IsNullOrEmpty(e.AudienceJson)
                ? new AudienceSpec { AllUsers = true }
                : (JsonSerializer.Deserialize<AudienceSpec>(e.AudienceJson, Json) ?? new AudienceSpec { AllUsers = true });
        }
        catch
        {
            audience = new AudienceSpec { AllUsers = true };
        }

        return new SystemAnnouncementDto
        {
            Id = e.Id,
            Title = e.Title,
            Content = e.Content,
            Kind = e.Kind,
            Severity = e.Severity,
            Status = e.Status,
            Channels = e.Channels,
            Audience = audience,
            ScheduleAt = e.ScheduleAt,
            ExpiresAt = e.ExpiresAt,
            RequireAck = e.RequireAck,
            AllowDismiss = e.AllowDismiss,
            ImageUrl = e.ImageUrl,
            ActionUrl = e.ActionUrl,
            ActionLabel = e.ActionLabel,
            RecipientCount = e.RecipientCount,
            DeliveredCount = e.DeliveredCount,
            SeenCount = e.SeenCount,
            ClickedCount = e.ClickedCount,
            AckedCount = e.AckedCount,
            SentAt = e.SentAt,
            CreatedAt = e.CreatedAt,
            CreatedBy = e.CreatedBy
        };
    }
}

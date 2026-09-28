using FirebaseAdmin.Messaging;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Services;
using ZKTecoADMS.Domain.Entities;
using FcmNotification = FirebaseAdmin.Messaging.Notification;

namespace ZKTecoADMS.Infrastructure.Services.Push;

public interface IPushNotificationService
{
    /// <summary>
    /// Send a push notification to every active token registered by <paramref name="userId"/>.
    /// Returns the number of tokens that succeeded. Tokens that Firebase reports as
    /// invalid/unregistered are marked disabled in the DB so they won't be retried.
    /// </summary>
    Task<int> PushToUserAsync(Guid userId, string title, string body,
        string? actionUrl = null, IDictionary<string, string>? data = null,
        string? androidTag = null,
        CancellationToken ct = default);

    /// <summary>Send to a list of users in parallel (one DB query for tokens).</summary>
    Task<int> PushToUsersAsync(IEnumerable<Guid> userIds, string title, string body,
        string? actionUrl = null, IDictionary<string, string>? data = null,
        string? androidTag = null,
        CancellationToken ct = default);

    /// <summary>Đưa badge iOS về 0. Android xóa khay khi app mở và gọi cancelAll.</summary>
    Task ClearBadgeAsync(Guid userId, CancellationToken ct = default);

    /// <summary>Cập nhật badge iOS = số chưa đọc hiện tại (sau khi đọc / bỏ đọc 1 thông báo).</summary>
    Task SyncBadgeAsync(Guid userId, CancellationToken ct = default);
}

public sealed class PushNotificationService : IPushNotificationService
{
    private readonly ZKTecoDbContext _db;
    private readonly FirebaseInitializer _firebase;
    private readonly ILogger<PushNotificationService> _logger;

    public PushNotificationService(ZKTecoDbContext db, FirebaseInitializer firebase, ILogger<PushNotificationService> logger)
    {
        _db = db; _firebase = firebase; _logger = logger;
    }

    public Task<int> PushToUserAsync(Guid userId, string title, string body,
        string? actionUrl = null, IDictionary<string, string>? data = null,
        string? androidTag = null,
        CancellationToken ct = default)
        => PushToUsersAsync(new[] { userId }, title, body, actionUrl, data, androidTag, ct);

    public async Task<int> PushToUsersAsync(IEnumerable<Guid> userIds, string title, string body,
        string? actionUrl = null, IDictionary<string, string>? data = null,
        string? androidTag = null,
        CancellationToken ct = default)
    {
        if (!_firebase.IsAvailable) return 0;

        var idList = userIds as IList<Guid> ?? userIds.ToList();
        if (idList.Count == 0) return 0;

        // Cài đặt đẩy theo tài khoản: tắt đẩy / giờ yên lặng.
        var settings = await _db.UserNotificationSettings.AsNoTracking()
            .Where(s => idList.Contains(s.UserId))
            .ToDictionaryAsync(s => s.UserId, ct);
        var pushOff = settings.Values.Where(s => !s.PushEnabled).Select(s => s.UserId).ToHashSet();

        var tokens = await _db.UserDeviceTokens.AsNoTracking()
            .Where(t => idList.Contains(t.UserId) && !t.IsDisabled)
            .Select(t => new { t.Id, t.Token, t.UserId })
            .ToListAsync(ct);
        tokens = tokens.Where(t => !pushOff.Contains(t.UserId)).ToList();
        if (tokens.Count == 0) return 0;

        var urgent = NotificationQuietRules.IsUrgent(
            data != null && data.TryGetValue("notificationType", out var nt) ? nt : null,
            data != null && data.TryGetValue("categoryCode", out var cc) ? cc : androidTag);
        var nowMinute = NotificationQuietRules.VnMinuteOfDay(DateTime.UtcNow);
        // Mỗi thông báo 1 tag riêng → không đè thông báo trước trong khay (trước đây cùng loại là đè nhau).
        var tag = data != null && data.TryGetValue("notificationId", out var nid) && !string.IsNullOrEmpty(nid)
            ? nid
            : $"{androidTag ?? "sbox"}_{Guid.NewGuid():N}";

        // Build common payload once.
        var payload = new Dictionary<string, string>(data ?? new Dictionary<string, string>());
        if (!string.IsNullOrEmpty(actionUrl)) payload["actionUrl"] = actionUrl!;

        // Chỉ đếm thông báo của đúng cửa hàng người nhận (và thông báo không gắn cửa hàng).
        var unreadGrouped = await (
            from n in _db.Notifications.IgnoreQueryFilters().AsNoTracking()
            join u in _db.Users.IgnoreQueryFilters().AsNoTracking() on n.TargetUserId equals u.Id
            where n.TargetUserId.HasValue
                  && idList.Contains(n.TargetUserId.Value)
                  && !n.IsRead
                  && (n.StoreId == null || n.StoreId == u.StoreId)
            group n by n.TargetUserId into g
            select new { UserId = g.Key, Count = g.Count() }
        ).ToListAsync(ct);
        var unreadByUser = unreadGrouped
            .Where(x => x.UserId.HasValue)
            .ToDictionary(x => x.UserId!.Value, x => x.Count);

        var notif = new FcmNotification { Title = title, Body = body };
        var success = 0;
        var invalidTokenIds = new List<Guid>();

        // We send per-user (multicast tokens of the same user together) so each
        // user gets their own APNs badge value. FCM SendEachAsync still batches
        // network calls on Google's side.
        foreach (var userGroup in tokens.GroupBy(t => t.UserId))
        {
            var badge = unreadByUser.TryGetValue(userGroup.Key, out var c) ? c : 0;
            var quiet = settings.TryGetValue(userGroup.Key, out var st)
                        && st.QuietEnabled
                        && NotificationQuietRules.IsInQuiet(nowMinute, st.QuietStartMinute, st.QuietEndMinute)
                        && !(urgent && st.AllowUrgentInQuiet);

            var apnsConfig = new ApnsConfig
            {
                Headers = new Dictionary<string, string>
                {
                    ["apns-priority"] = quiet ? "5" : "10",
                    ["apns-push-type"] = "alert",
                },
                Aps = new Aps
                {
                    // Giờ yên lặng: vẫn hiện trong trung tâm thông báo nhưng không chuông.
                    Sound = quiet ? null : "default",
                    Badge = badge,
                    ContentAvailable = true,
                    ThreadId = androidTag ?? "sbox_hrm",
                },
            };

            var tokenList = userGroup.Select(t => new { t.Id, t.Token }).ToList();
            // Chunk per user just in case a user has > 500 devices (defensive).
            const int chunkSize = 500;
            for (int i = 0; i < tokenList.Count; i += chunkSize)
            {
                var chunk = tokenList.Skip(i).Take(chunkSize).ToList();
                var msg = new MulticastMessage
                {
                    Tokens = chunk.Select(t => t.Token).ToList(),
                    Notification = notif,
                    Data = payload,
                    Apns = apnsConfig,
                    Android = new AndroidConfig
                    {
                        Priority = quiet ? Priority.Normal : Priority.High,
                        Notification = new AndroidNotification
                        {
                            Tag = tag,
                            ChannelId = quiet ? "attendance_quiet" : (urgent ? "attendance_urgent" : "attendance_default"),
                            NotificationCount = badge,
                            Sound = quiet ? null : "default",
                        },
                    },
                };
                try
                {
                    var resp = await FirebaseMessaging.DefaultInstance.SendEachForMulticastAsync(msg, ct);
                    success += resp.SuccessCount;

                    if (resp.FailureCount > 0)
                    {
                        for (int r = 0; r < resp.Responses.Count; r++)
                        {
                            var sr = resp.Responses[r];
                            if (sr.IsSuccess) continue;
                            var ec = sr.Exception?.MessagingErrorCode;
                            if (ec == MessagingErrorCode.Unregistered || ec == MessagingErrorCode.InvalidArgument)
                            {
                                invalidTokenIds.Add(chunk[r].Id);
                            }
                            else
                            {
                                _logger.LogWarning(sr.Exception,
                                    "FCM transient failure for token {TokenId}: {Code}", chunk[r].Id, ec);
                            }
                        }
                    }
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "FCM multicast send failed (chunk size {Size}, user {UserId})",
                        chunk.Count, userGroup.Key);
                }
            }
        }

        if (invalidTokenIds.Count > 0)
        {
            await _db.UserDeviceTokens
                .Where(t => invalidTokenIds.Contains(t.Id))
                .ExecuteUpdateAsync(s => s.SetProperty(t => t.IsDisabled, true), ct);
            _logger.LogInformation("Disabled {Count} stale FCM tokens", invalidTokenIds.Count);
        }

        if (success > 0)
        {
            // We approximate "delivered" by all attempted tokens minus invalid ones.
            var liveIds = tokens.Where(t => !invalidTokenIds.Contains(t.Id)).Select(t => t.Id).ToList();
            await _db.UserDeviceTokens
                .Where(t => liveIds.Contains(t.Id))
                .ExecuteUpdateAsync(s => s.SetProperty(t => t.LastUsedAt, DateTime.UtcNow), ct);
        }

        return success;
    }

    public Task ClearBadgeAsync(Guid userId, CancellationToken ct = default) => SendBadgeAsync(userId, 0, ct);

    public async Task SyncBadgeAsync(Guid userId, CancellationToken ct = default)
    {
        if (!_firebase.IsAvailable) return;
        var unread = await (
            from n in _db.Notifications.IgnoreQueryFilters().AsNoTracking()
            join u in _db.Users.IgnoreQueryFilters().AsNoTracking() on n.TargetUserId equals u.Id
            where n.TargetUserId == userId && !n.IsRead && (n.StoreId == null || n.StoreId == u.StoreId)
            select n.Id).CountAsync(ct);
        await SendBadgeAsync(userId, unread, ct);
    }

    private async Task SendBadgeAsync(Guid userId, int badge, CancellationToken ct)
    {
        if (!_firebase.IsAvailable) return;

        var tokens = await _db.UserDeviceTokens.AsNoTracking()
            .Where(t => t.UserId == userId && !t.IsDisabled)
            .Select(t => t.Token)
            .ToListAsync(ct);
        if (tokens.Count == 0) return;

        var msg = new MulticastMessage
        {
            Tokens = tokens,
            Data = new Dictionary<string, string>
            {
                ["type"] = badge == 0 ? "badge_clear" : "badge_sync",
                ["badge"] = badge.ToString(),
            },
            Apns = new ApnsConfig
            {
                Headers = new Dictionary<string, string>
                {
                    ["apns-priority"] = "5",
                    ["apns-push-type"] = "background",
                },
                Aps = new Aps
                {
                    Badge = badge,
                    ContentAvailable = true,
                },
            },
            Android = new AndroidConfig
            {
                Priority = Priority.Normal,
                CollapseKey = "sbox_badge",
            },
        };

        try
        {
            await FirebaseMessaging.DefaultInstance.SendEachForMulticastAsync(msg, ct);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "FCM badge clear failed for {UserId}", userId);
        }
    }
}

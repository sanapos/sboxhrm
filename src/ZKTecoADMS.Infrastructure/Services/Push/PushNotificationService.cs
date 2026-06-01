using FirebaseAdmin.Messaging;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using ZKTecoADMS.Application.Interfaces;
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

        var tokens = await _db.UserDeviceTokens.AsNoTracking()
            .Where(t => idList.Contains(t.UserId) && !t.IsDisabled)
            .Select(t => new { t.Id, t.Token, t.UserId })
            .ToListAsync(ct);
        if (tokens.Count == 0) return 0;

        // Build common payload once.
        var payload = new Dictionary<string, string>(data ?? new Dictionary<string, string>());
        if (!string.IsNullOrEmpty(actionUrl)) payload["actionUrl"] = actionUrl!;

        // Per-user unread count for iOS badge + Android notification_count (inbox summary).
        var unreadGrouped = await _db.Notifications.AsNoTracking()
            .Where(n => n.TargetUserId.HasValue
                        && idList.Contains(n.TargetUserId.Value)
                        && !n.IsRead)
            .GroupBy(n => n.TargetUserId)
            .Select(g => new { UserId = g.Key, Count = g.Count() })
            .ToListAsync(ct);
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

            var apnsConfig = new ApnsConfig
            {
                Headers = new Dictionary<string, string>
                {
                    ["apns-priority"] = "10",
                    ["apns-push-type"] = "alert",
                },
                Aps = new Aps
                {
                    Sound = "default",
                    Badge = badge,
                    ContentAvailable = true,
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
                        CollapseKey = androidTag ?? "sbox_hrm",
                        Notification = new AndroidNotification
                        {
                            Tag = androidTag ?? "sbox_hrm",
                            ChannelId = "attendance_default",
                            NotificationCount = badge > 0 ? badge : null,
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
}

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
        CancellationToken ct = default);

    /// <summary>Send to a list of users in parallel (one DB query for tokens).</summary>
    Task<int> PushToUsersAsync(IEnumerable<Guid> userIds, string title, string body,
        string? actionUrl = null, IDictionary<string, string>? data = null,
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
        CancellationToken ct = default)
        => PushToUsersAsync(new[] { userId }, title, body, actionUrl, data, ct);

    public async Task<int> PushToUsersAsync(IEnumerable<Guid> userIds, string title, string body,
        string? actionUrl = null, IDictionary<string, string>? data = null,
        CancellationToken ct = default)
    {
        if (!_firebase.IsAvailable) return 0;

        var idList = userIds as IList<Guid> ?? userIds.ToList();
        if (idList.Count == 0) return 0;

        var tokens = await _db.UserDeviceTokens.AsNoTracking()
            .Where(t => idList.Contains(t.UserId) && !t.IsDisabled)
            .Select(t => new { t.Id, t.Token })
            .ToListAsync(ct);
        if (tokens.Count == 0) return 0;

        // Build common payload once; FCM has a limit of 500 tokens per multicast.
        var payload = new Dictionary<string, string>(data ?? new Dictionary<string, string>());
        if (!string.IsNullOrEmpty(actionUrl)) payload["actionUrl"] = actionUrl!;

        var notif = new FcmNotification { Title = title, Body = body };
        var success = 0;
        var invalidTokenIds = new List<Guid>();

        // FCM v1 multicast: chunk to 500.
        const int chunkSize = 500;
        for (int i = 0; i < tokens.Count; i += chunkSize)
        {
            var chunk = tokens.Skip(i).Take(chunkSize).ToList();
            var msg = new MulticastMessage
            {
                Tokens = chunk.Select(t => t.Token).ToList(),
                Notification = notif,
                Data = payload,
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
                        // UNREGISTERED / INVALID_ARGUMENT mean the token will never work again.
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
                _logger.LogError(ex, "FCM multicast send failed (chunk size {Size})", chunk.Count);
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
            // Update LastUsedAt for the tokens that delivered. Best-effort, skip on conflict.
            // We approximate "delivered" by all attempted tokens minus invalid ones; FCM
            // doesn't tell us which specific tokens succeeded vs failed transiently.
            var liveIds = tokens.Where(t => !invalidTokenIds.Contains(t.Id)).Select(t => t.Id).ToList();
            await _db.UserDeviceTokens
                .Where(t => liveIds.Contains(t.Id))
                .ExecuteUpdateAsync(s => s.SetProperty(t => t.LastUsedAt, DateTime.UtcNow), ct);
        }

        return success;
    }
}

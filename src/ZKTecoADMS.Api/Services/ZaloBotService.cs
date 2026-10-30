using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Zalo bot của cửa hàng: kết nối token (getMe + setWebhook), liên kết tài khoản bằng mã 6 số, xử lý tin người dùng
/// gửi bot (webhook), đưa thông báo vào hàng đợi và gửi hàng đợi (job nền).
/// </summary>
public sealed class ZaloBotService(
    ZKTecoDbContext db,
    IZaloBotClient client,
    ZaloBotSecrets secrets,
    ILogger<ZaloBotService> logger)
{
    public static readonly TimeSpan LinkCodeLifetime = TimeSpan.FromMinutes(15);
    public const int MaxAttempts = 5;

    public const int Pending = 0, Sending = 1, Sent = 2, Failed = 3;

    public static string WebhookUrl(string baseUrl, Guid settingId) =>
        $"{baseUrl.TrimEnd('/')}/api/zalo-bot/webhook/{settingId}";

    public string? Token(ZaloBotSetting s) => secrets.Unprotect(s.BotTokenEnc);

    // ─── Kết nối bot ─────────────────────────────────────────────

    /// <summary>
    /// Kiểm tra token (getMe), lưu token mã hóa + tên bot, tạo bí mật webhook mới và đăng ký webhook.
    /// <paramref name="s"/> phải đang được theo dõi (AsTracking) — người gọi SaveChanges.
    /// </summary>
    public async Task<string?> ConnectAsync(ZaloBotSetting s, string token, string webhookBaseUrl, CancellationToken ct)
    {
        token = token.Trim();
        var me = await client.GetMeAsync(token, ct);
        if (!me.Ok)
            return me.TokenInvalid ? "Token bot không đúng hoặc đã hết hạn." : $"Không kiểm tra được token: {me.Error}";

        s.BotTokenEnc = secrets.Protect(token);
        if (me.Result is { ValueKind: JsonValueKind.Object } r)
        {
            s.BotId = Str(r, "id");
            s.BotName = Str(r, "account_name") ?? Str(r, "display_name");
        }
        s.WebhookSecret = ZaloBotText.NewSecret();
        await RegisterWebhookAsync(s, token, webhookBaseUrl, ct);
        return null;
    }

    /// <summary>Đăng ký (lại) webhook. Lỗi ghi vào LastError, không chặn việc lưu token.</summary>
    public async Task RegisterWebhookAsync(ZaloBotSetting s, string token, string webhookBaseUrl, CancellationToken ct)
    {
        if (string.IsNullOrEmpty(s.WebhookSecret)) s.WebhookSecret = ZaloBotText.NewSecret();
        var res = await client.SetWebhookAsync(token, WebhookUrl(webhookBaseUrl, s.Id), s.WebhookSecret, ct);
        s.WebhookOk = res.Ok;
        s.LastError = res.Ok ? null : ZaloBotText.Truncate($"Đăng ký webhook lỗi: {res.Error}", 500);
    }

    // ─── Liên kết tài khoản ──────────────────────────────────────

    /// <summary>Cấp mã 6 số mới (hết hạn sau 15 phút) — không trùng mã đang chờ khác trong cửa hàng.</summary>
    public async Task<ZaloBotLink> CreateLinkCodeAsync(Guid storeId, Guid userId, DateTime now, CancellationToken ct)
    {
        var link = await db.ZaloBotLinks.AsTracking().FirstOrDefaultAsync(l => l.StoreId == storeId && l.UserId == userId, ct);
        if (link == null)
        {
            link = new ZaloBotLink { Id = Guid.NewGuid(), StoreId = storeId, UserId = userId, CreatedBy = userId.ToString() };
            db.ZaloBotLinks.Add(link);
        }
        else
        {
            link.UpdatedAt = now;
        }

        string code;
        var tries = 0;
        do
        {
            code = ZaloBotText.NewLinkCode();
        } while (++tries < 10 && await db.ZaloBotLinks.AnyAsync(l => l.StoreId == storeId && l.UserId != userId
                     && l.PendingCode == code && l.PendingCodeExpiresAt > now, ct));

        link.PendingCode = code;
        link.PendingCodeExpiresAt = now.Add(LinkCodeLifetime);
        await db.SaveChangesAsync(ct);
        return link;
    }

    public async Task<bool> UnlinkAsync(Guid storeId, Guid userId, CancellationToken ct)
    {
        var link = await db.ZaloBotLinks.AsTracking().FirstOrDefaultAsync(l => l.StoreId == storeId && l.UserId == userId, ct);
        if (link?.ChatId == null) return false;
        link.ChatId = null;
        link.ZaloName = null;
        link.LinkedAt = null;
        link.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync(ct);
        return true;
    }

    // ─── Webhook ─────────────────────────────────────────────────

    /// <summary>
    /// Tin người dùng gửi bot. Trả mã HTTP: 404 bot không tồn tại, 403 sai bí mật, 200 đã xử lý (kể cả tin bỏ qua —
    /// trả lỗi thì Zalo gửi lại).
    /// </summary>
    public async Task<int> HandleWebhookAsync(Guid settingId, string? secretHeader, JsonElement payload, DateTime now, CancellationToken ct)
    {
        var s = await db.ZaloBotSettings.FirstOrDefaultAsync(x => x.Id == settingId, ct);
        if (s == null) return 404;
        if (string.IsNullOrEmpty(s.WebhookSecret) || !SecretEquals(s.WebhookSecret, secretHeader)) return 403;

        var root = payload;
        if (root.ValueKind == JsonValueKind.Object && root.TryGetProperty("result", out var inner) && inner.ValueKind == JsonValueKind.Object)
            root = inner;
        if (root.ValueKind != JsonValueKind.Object || !root.TryGetProperty("message", out var msg) || msg.ValueKind != JsonValueKind.Object)
            return 200;

        var chatId = msg.TryGetProperty("chat", out var chat) && chat.ValueKind == JsonValueKind.Object ? Str(chat, "id") : null;
        var from = msg.TryGetProperty("from", out var f) && f.ValueKind == JsonValueKind.Object ? f : default;
        chatId ??= from.ValueKind == JsonValueKind.Object ? Str(from, "id") : null;
        if (string.IsNullOrEmpty(chatId)) return 200;
        if (from.ValueKind == JsonValueKind.Object && from.TryGetProperty("is_bot", out var isBot) && isBot.ValueKind == JsonValueKind.True)
            return 200;

        var zaloName = from.ValueKind == JsonValueKind.Object ? Str(from, "display_name") : null;
        var text = Str(msg, "text");
        var reply = await BuildReplyAsync(s, chatId, zaloName, text, now, ct);

        var token = Token(s);
        if (reply != null && token != null)
        {
            var r = await client.SendMessageAsync(token, chatId, reply, ct);
            if (!r.Ok) logger.LogWarning("Zalo bot reply failed for store {StoreId}: {Error}", s.StoreId, r.Error);
        }
        return 200;
    }

    async Task<string?> BuildReplyAsync(ZaloBotSetting s, string chatId, string? zaloName, string? text, DateTime now, CancellationToken ct)
    {
        var storeName = await db.Stores.Where(x => x.Id == s.StoreId).Select(x => x.Name).FirstOrDefaultAsync(ct) ?? "cửa hàng";

        if (ZaloBotText.ExtractLinkCode(text) is string code)
        {
            var link = await db.ZaloBotLinks.AsTracking().FirstOrDefaultAsync(l => l.StoreId == s.StoreId
                && l.PendingCode == code && l.PendingCodeExpiresAt > now, ct);
            if (link == null)
                return "Mã không đúng hoặc đã hết hạn. Mở app SBOX › Cài đặt › Liên kết Zalo để lấy mã mới.";

            link.ChatId = chatId;
            link.ZaloName = zaloName == null ? null : ZaloBotText.Truncate(zaloName, 200);
            link.LinkedAt = now;
            link.PendingCode = null;
            link.PendingCodeExpiresAt = null;
            link.UpdatedAt = now;
            await db.SaveChangesAsync(ct);
            var name = await UserNameAsync(link.UserId, ct);
            return $"✅ Đã liên kết Zalo với tài khoản {name} tại {storeName}.\n" +
                   "Từ giờ thông báo lương, phạt, duyệt đơn… sẽ gửi về đây.\nGửi «HUY» để hủy liên kết.";
        }

        var linked = await db.ZaloBotLinks.AsTracking()
            .Where(l => l.StoreId == s.StoreId && l.ChatId == chatId).ToListAsync(ct);

        if (ZaloBotText.IsUnlinkCommand(text))
        {
            if (linked.Count == 0) return "Zalo này chưa liên kết tài khoản nào.";
            foreach (var l in linked)
            {
                l.ChatId = null;
                l.ZaloName = null;
                l.LinkedAt = null;
                l.UpdatedAt = now;
            }
            await db.SaveChangesAsync(ct);
            return $"Đã hủy liên kết. Bạn sẽ không nhận thông báo của {storeName} qua Zalo nữa.";
        }

        if (linked.Count > 0)
        {
            var names = new List<string>();
            foreach (var l in linked) names.Add(await UserNameAsync(l.UserId, ct));
            return $"Bạn đang nhận thông báo của {storeName} cho tài khoản {string.Join(", ", names)}.\n" +
                   "Xem chi tiết trong app SBOX. Gửi «HUY» để hủy liên kết.";
        }

        return $"Xin chào! Đây là bot thông báo của {storeName}.\n" +
               "Để nhận thông báo lương, chấm công…: mở app SBOX › Cài đặt › Liên kết Zalo, lấy mã 6 số rồi gửi mã đó vào đây.";
    }

    async Task<string> UserNameAsync(Guid userId, CancellationToken ct)
    {
        var u = await db.Users.Where(x => x.Id == userId)
            .Select(x => new { x.FirstName, x.LastName, x.UserName }).FirstOrDefaultAsync(ct);
        var full = $"{u?.FirstName} {u?.LastName}".Trim();
        return full.Length > 0 ? full : u?.UserName ?? "của bạn";
    }

    static bool SecretEquals(string expected, string? actual) =>
        actual != null && CryptographicOperations.FixedTimeEquals(Encoding.UTF8.GetBytes(expected), Encoding.UTF8.GetBytes(actual));

    static string? Str(JsonElement e, string name) =>
        e.TryGetProperty(name, out var v)
            ? v.ValueKind switch
            {
                JsonValueKind.String => v.GetString(),
                JsonValueKind.Number => v.GetRawText(),
                _ => null,
            }
            : null;

    // ─── Hàng đợi ────────────────────────────────────────────────

    /// <summary>
    /// Thông báo vừa lưu → tin Zalo chờ gửi cho người nhận đã liên kết, nếu cửa hàng bật bot và nhóm thông báo
    /// nằm trong danh sách gửi Zalo. Trả số tin đã đưa vào hàng đợi.
    /// </summary>
    public static async Task<int> EnqueueAsync(ZKTecoDbContext db, IReadOnlyCollection<Notification> notifications,
        string? appLink, CancellationToken ct = default)
    {
        var count = 0;
        foreach (var group in notifications.Where(n => n.StoreId != null && n.TargetUserId != null).GroupBy(n => n.StoreId!.Value))
        {
            var s = await db.ZaloBotSettings.FirstOrDefaultAsync(x => x.StoreId == group.Key, ct);
            if (s is not { Enabled: true } || string.IsNullOrEmpty(s.BotTokenEnc)) continue;
            var cats = ZaloBotText.ParseCategories(s.Categories).ToHashSet();
            var items = group.Where(n => NotificationCategoryCodes.Normalize(n.CategoryCode) is string c && cats.Contains(c)).ToList();
            if (items.Count == 0) continue;

            var userIds = items.Select(n => n.TargetUserId!.Value).Distinct().ToList();
            var chats = await db.ZaloBotLinks
                .Where(l => l.StoreId == group.Key && userIds.Contains(l.UserId) && l.ChatId != null)
                .ToDictionaryAsync(l => l.UserId, l => l.ChatId!, ct);
            foreach (var n in items)
            {
                if (!chats.TryGetValue(n.TargetUserId!.Value, out var chatId)) continue;
                var link = n.RelatedUrl != null && n.RelatedUrl.StartsWith("http", StringComparison.OrdinalIgnoreCase)
                    ? n.RelatedUrl : appLink;
                db.ZaloBotMessages.Add(new ZaloBotMessage
                {
                    Id = Guid.NewGuid(),
                    StoreId = group.Key,
                    UserId = n.TargetUserId,
                    ChatId = chatId,
                    Text = ZaloBotText.FormatNotification(n.Title ?? "", n.Message ?? "", s.HideMoney, link),
                    NotificationId = n.Id,
                    CategoryCode = NotificationCategoryCodes.Normalize(n.CategoryCode),
                    Status = Pending,
                    NextAttemptAt = DateTime.UtcNow,
                });
                count++;
            }
        }
        if (count > 0) await db.SaveChangesAsync(ct);
        return count;
    }

    /// <summary>Thử lại sau 1, 5, 15, 60 phút.</summary>
    public static TimeSpan Backoff(int attempts) => attempts switch
    {
        <= 1 => TimeSpan.FromMinutes(1),
        2 => TimeSpan.FromMinutes(5),
        3 => TimeSpan.FromMinutes(15),
        _ => TimeSpan.FromMinutes(60),
    };

    /// <summary>Gửi các tin đến hạn. Trả số tin gửi thành công.</summary>
    public async Task<int> ProcessBatchAsync(DateTime now, int take, CancellationToken ct)
    {
        var due = await db.ZaloBotMessages.AsTracking()
            .Where(m => m.Status == Pending && m.NextAttemptAt <= now)
            .OrderBy(m => m.NextAttemptAt)
            .Take(take)
            .ToListAsync(ct);
        if (due.Count == 0) return 0;

        foreach (var m in due)
        {
            m.Status = Sending;
            m.UpdatedAt = now;
        }
        await db.SaveChangesAsync(ct);

        var sent = 0;
        foreach (var group in due.GroupBy(m => m.StoreId))
        {
            var s = await db.ZaloBotSettings.AsTracking().FirstOrDefaultAsync(x => x.StoreId == group.Key, ct);
            var token = s is { Enabled: true } ? Token(s) : null;
            var tokenDead = false;
            foreach (var m in group)
            {
                if (token == null || tokenDead)
                {
                    if (token == null) Fail(m, "Zalo bot đã tắt hoặc chưa có token", now);
                    else Retry(m, "Token bot không hợp lệ", now);
                    continue;
                }

                var r = await client.SendMessageAsync(token, m.ChatId, m.Text, ct);
                if (r.Ok)
                {
                    m.Status = Sent;
                    m.SentAt = now;
                    m.Attempts++;
                    m.Error = null;
                    sent++;
                }
                else if (r.TokenInvalid)
                {
                    tokenDead = true;
                    Retry(m, r.Error, now);
                    s!.LastError = "Token bot không đúng hoặc đã hết hạn — nhập lại token trong Thiết lập SBOX › Zalo bot.";
                    s.UpdatedAt = now;
                }
                else
                {
                    Retry(m, r.Error, now);
                }
            }
            await db.SaveChangesAsync(ct);
        }
        return sent;
    }

    static void Retry(ZaloBotMessage m, string error, DateTime now)
    {
        m.Attempts++;
        m.Error = ZaloBotText.Truncate(error, 500);
        m.UpdatedAt = now;
        if (m.Attempts >= MaxAttempts)
        {
            m.Status = Failed;
            return;
        }
        m.Status = Pending;
        m.NextAttemptAt = now.Add(Backoff(m.Attempts));
    }

    static void Fail(ZaloBotMessage m, string error, DateTime now)
    {
        m.Status = Failed;
        m.Error = error;
        m.UpdatedAt = now;
    }

    /// <summary>Tin kẹt «đang gửi» (máy chủ tắt giữa chừng) → gửi lại; xóa tin cũ hơn 30 ngày.</summary>
    public async Task CleanupAsync(DateTime now, CancellationToken ct)
    {
        var stuckBefore = now.AddMinutes(-10);
        await db.ZaloBotMessages
            .Where(m => m.Status == Sending && m.UpdatedAt < stuckBefore)
            .ExecuteUpdateAsync(u => u.SetProperty(m => m.Status, Pending), ct);
        var oldBefore = now.AddDays(-30);
        await db.ZaloBotMessages
            .Where(m => (m.Status == Sent || m.Status == Failed) && m.CreatedAt < oldBefore)
            .ExecuteDeleteAsync(ct);
    }
}

/// <summary>Đưa thông báo vào hàng đợi Zalo trong DbContext riêng — không lưu hộ thay đổi dở dang của người gọi.</summary>
public interface IZaloBotOutbox
{
    Task EnqueueAsync(IReadOnlyCollection<Notification> notifications);
}

public sealed class ZaloBotOutbox(IServiceScopeFactory scopes, IConfiguration config, ILogger<ZaloBotOutbox> logger) : IZaloBotOutbox
{
    public async Task EnqueueAsync(IReadOnlyCollection<Notification> notifications)
    {
        if (notifications.Count == 0) return;
        try
        {
            await using var scope = scopes.CreateAsyncScope();
            var db = scope.ServiceProvider.GetRequiredService<ZKTecoDbContext>();
            await ZaloBotService.EnqueueAsync(db, notifications, AppLink(config));
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Zalo bot enqueue failed");
        }
    }

    /// <summary>Link mở app kèm trong tin.</summary>
    public static string AppLink(IConfiguration config) =>
        config["ZaloBot:AppLink"] ?? config["AppSettings:FlutterClientUrl"] ?? "https://sboxhrm.com";
}

/// <summary>Mỗi 5 giây gửi tin Zalo đến hạn; mỗi giờ dọn tin cũ.</summary>
public class ZaloBotSendBackgroundService(IServiceProvider sp, ILogger<ZaloBotSendBackgroundService> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        await Task.Delay(TimeSpan.FromSeconds(20), stoppingToken);
        var lastCleanup = DateTime.MinValue;
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                using var scope = sp.CreateScope();
                var svc = scope.ServiceProvider.GetRequiredService<ZaloBotService>();
                var now = DateTime.UtcNow;
                if (now - lastCleanup > TimeSpan.FromHours(1))
                {
                    await svc.CleanupAsync(now, stoppingToken);
                    lastCleanup = now;
                }
                await svc.ProcessBatchAsync(now, 50, stoppingToken);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                break;
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "Zalo bot send loop failed");
            }
            await Task.Delay(TimeSpan.FromSeconds(5), stoppingToken);
        }
    }
}

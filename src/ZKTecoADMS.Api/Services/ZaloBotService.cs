using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
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

    /// <summary>Mã in trên bảng liên kết cả cửa hàng — phát cho nhân viên dần trong tuần nên sống lâu hơn.</summary>
    public static readonly TimeSpan TableCodeLifetime = TimeSpan.FromDays(7);
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
        var employeeId = await db.Employees
            .Where(e => e.StoreId == storeId && e.ApplicationUserId == userId)
            .Select(e => (Guid?)e.Id).FirstOrDefaultAsync(ct);
        var link = await FindLinkAsync(storeId, userId, employeeId, ct);
        if (link == null)
        {
            link = new ZaloBotLink { Id = Guid.NewGuid(), StoreId = storeId, CreatedBy = userId.ToString() };
            db.ZaloBotLinks.Add(link);
        }
        else
        {
            link.UpdatedAt = now;
        }
        link.UserId = userId;
        link.EmployeeId ??= employeeId;

        link.PendingCode = await NewUniqueCodeAsync(storeId, link.Id, now, ct);
        link.PendingCodeExpiresAt = now.Add(LinkCodeLifetime);
        await db.SaveChangesAsync(ct);
        return link;
    }

    /// <summary>Dòng liên kết của một người: theo tài khoản, hoặc theo hồ sơ nhân viên (bảng mã tạo trước khi có tài khoản).</summary>
    async Task<ZaloBotLink?> FindLinkAsync(Guid storeId, Guid? userId, Guid? employeeId, CancellationToken ct)
    {
        ZaloBotLink? link = null;
        if (userId != null)
            link = await db.ZaloBotLinks.AsTracking().FirstOrDefaultAsync(l => l.StoreId == storeId && l.UserId == userId, ct);
        if (link == null && employeeId != null)
            link = await db.ZaloBotLinks.AsTracking().FirstOrDefaultAsync(l => l.StoreId == storeId && l.EmployeeId == employeeId, ct);
        return link;
    }

    /// <summary>Mã 6 số không trùng mã đang chờ của người khác trong cửa hàng.</summary>
    async Task<string> NewUniqueCodeAsync(Guid storeId, Guid linkId, DateTime now, CancellationToken ct, ISet<string>? taken = null)
    {
        string code;
        var tries = 0;
        do
        {
            code = ZaloBotText.NewLinkCode();
        } while (++tries < 20 && ((taken?.Contains(code) ?? false)
                     || await db.ZaloBotLinks.AnyAsync(l => l.StoreId == storeId && l.Id != linkId
                         && l.PendingCode == code && l.PendingCodeExpiresAt > now, ct)));
        taken?.Add(code);
        return code;
    }

    public sealed record EmployeeLinkRow(
        Guid? EmployeeId, Guid? UserId, string Name, string? EmployeeCode, string? Department, string? Phone,
        bool HasAccount, bool Linked, string? ZaloName, DateTime? LinkedAt, string? Code, DateTime? CodeExpiresAt);

    /// <summary>
    /// Bảng liên kết cả cửa hàng: mọi nhân viên đang làm (kể cả không có tài khoản) + tài khoản đã liên kết không gắn hồ sơ.
    /// Mã chỉ hiện khi còn hạn.
    /// </summary>
    public async Task<List<EmployeeLinkRow>> EmployeeLinksAsync(Guid storeId, DateTime now, CancellationToken ct)
    {
        var employees = await db.Employees
            .Where(e => e.StoreId == storeId && e.WorkStatus != EmployeeWorkStatus.Resigned)
            .Select(e => new { e.Id, e.FirstName, e.LastName, e.EmployeeCode, e.Department, e.PhoneNumber, e.ApplicationUserId })
            .ToListAsync(ct);
        var links = await db.ZaloBotLinks.Where(l => l.StoreId == storeId).ToListAsync(ct);
        var byEmployee = links.Where(l => l.EmployeeId != null).GroupBy(l => l.EmployeeId!.Value).ToDictionary(g => g.Key, g => g.First());
        var byUser = links.Where(l => l.UserId != null).GroupBy(l => l.UserId!.Value).ToDictionary(g => g.Key, g => g.First());

        var rows = new List<EmployeeLinkRow>();
        var used = new HashSet<Guid>();
        foreach (var e in employees)
        {
            ZaloBotLink? l = null;
            if (!byEmployee.TryGetValue(e.Id, out l) && e.ApplicationUserId != null) byUser.TryGetValue(e.ApplicationUserId.Value, out l);
            if (l != null) used.Add(l.Id);
            rows.Add(Row(e.Id, e.ApplicationUserId, $"{e.FirstName} {e.LastName}".Trim(), e.EmployeeCode, e.Department, e.PhoneNumber, l, now));
        }

        // Tài khoản đã liên kết mà không có hồ sơ nhân viên (chủ cửa hàng…).
        var orphanUserIds = links.Where(l => !used.Contains(l.Id) && l.ChatId != null && l.UserId != null).Select(l => l.UserId!.Value).ToList();
        if (orphanUserIds.Count > 0)
        {
            var users = await db.Users.Where(u => orphanUserIds.Contains(u.Id))
                .Select(u => new { u.Id, u.FirstName, u.LastName, u.UserName, u.PhoneNumber }).ToListAsync(ct);
            foreach (var u in users)
            {
                var name = $"{u.FirstName} {u.LastName}".Trim();
                rows.Add(Row(null, u.Id, name.Length > 0 ? name : u.UserName ?? "", null, null, u.PhoneNumber, byUser[u.Id], now));
            }
        }
        return rows.OrderBy(r => r.Linked).ThenBy(r => r.Department ?? "\uffff").ThenBy(r => r.Name).ToList();
    }

    static EmployeeLinkRow Row(Guid? employeeId, Guid? userId, string name, string? code, string? dept, string? phone,
        ZaloBotLink? l, DateTime now)
    {
        var linked = l?.ChatId != null;
        var codeValid = !linked && l?.PendingCode != null && l.PendingCodeExpiresAt > now;
        return new EmployeeLinkRow(employeeId, userId, name, string.IsNullOrWhiteSpace(code) ? null : code, dept, phone,
            userId != null, linked, linked ? l!.ZaloName : null, linked ? l!.LinkedAt : null,
            codeValid ? l!.PendingCode : null, codeValid ? l!.PendingCodeExpiresAt : null);
    }

    /// <summary>
    /// Cấp mã liên kết (hạn 7 ngày) cho nhân viên chưa liên kết. <paramref name="employeeIds"/> null = mọi nhân viên đang làm.
    /// Mã còn hạn giữ nguyên (in lại bảng không làm hỏng mã đã phát), trừ khi <paramref name="renew"/>.
    /// Trả số mã mới cấp.
    /// </summary>
    public async Task<int> CreateEmployeeLinkCodesAsync(Guid storeId, IReadOnlyCollection<Guid>? employeeIds, bool renew,
        Guid byUserId, DateTime now, CancellationToken ct)
    {
        var q = db.Employees.Where(e => e.StoreId == storeId && e.WorkStatus != EmployeeWorkStatus.Resigned);
        if (employeeIds != null) q = q.Where(e => employeeIds.Contains(e.Id));
        var employees = await q.Select(e => new { e.Id, e.ApplicationUserId }).ToListAsync(ct);
        if (employees.Count == 0) return 0;

        var links = await db.ZaloBotLinks.AsTracking().Where(l => l.StoreId == storeId).ToListAsync(ct);
        var taken = links.Where(l => l.PendingCode != null && l.PendingCodeExpiresAt > now).Select(l => l.PendingCode!).ToHashSet();
        var created = 0;
        foreach (var e in employees)
        {
            var link = links.FirstOrDefault(l => l.EmployeeId == e.Id)
                       ?? (e.ApplicationUserId == null ? null : links.FirstOrDefault(l => l.UserId == e.ApplicationUserId));
            if (link?.ChatId != null) continue;
            if (link == null)
            {
                link = new ZaloBotLink { Id = Guid.NewGuid(), StoreId = storeId, CreatedBy = byUserId.ToString() };
                db.ZaloBotLinks.Add(link);
                links.Add(link);
            }
            else
            {
                link.UpdatedAt = now;
            }
            link.EmployeeId = e.Id;
            link.UserId ??= e.ApplicationUserId;
            if (!renew && link.PendingCode != null && link.PendingCodeExpiresAt > now) continue;
            if (link.PendingCode != null) taken.Remove(link.PendingCode);
            link.PendingCode = await NewUniqueCodeAsync(storeId, link.Id, now, ct, taken);
            link.PendingCodeExpiresAt = now.Add(TableCodeLifetime);
            created++;
        }
        await db.SaveChangesAsync(ct);
        return created;
    }

    public async Task<bool> UnlinkAsync(Guid storeId, Guid userId, CancellationToken ct)
    {
        var link = await db.ZaloBotLinks.AsTracking().FirstOrDefaultAsync(l => l.StoreId == storeId && l.UserId == userId, ct);
        return await ClearAsync(link, ct);
    }

    public async Task<bool> UnlinkEmployeeAsync(Guid storeId, Guid employeeId, CancellationToken ct)
    {
        var userId = await db.Employees.Where(e => e.Id == employeeId && e.StoreId == storeId)
            .Select(e => e.ApplicationUserId).FirstOrDefaultAsync(ct);
        return await ClearAsync(await FindLinkAsync(storeId, userId, employeeId, ct), ct);
    }

    async Task<bool> ClearAsync(ZaloBotLink? link, CancellationToken ct)
    {
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
                return "❌ MÃ KHÔNG HỢP LỆ\n" + ZaloBotText.Divider + "\n" +
                       "Mã không đúng hoặc đã hết hạn.\n\n" +
                       "Lấy mã mới:\n" +
                       "• Có tài khoản app: Cài đặt › Liên kết Zalo\n" +
                       "• Không có tài khoản: xin quản lý phiếu mã mới";

            link.ChatId = chatId;
            link.ZaloName = zaloName == null ? null : ZaloBotText.Truncate(zaloName, 200);
            link.LinkedAt = now;
            link.PendingCode = null;
            link.PendingCodeExpiresAt = null;
            link.UpdatedAt = now;
            await db.SaveChangesAsync(ct);
            var name = await PersonNameAsync(link, ct);
            var cats = ZaloBotText.ParseCategories(s.Categories)
                .Select(c => ZaloBotText.AllCategories.First(x => x.Code == c).Label).ToList();
            // «Đã liên kết» khớp câu hướng dẫn ở app / phiếu in («Bot trả lời «Đã liên kết» là xong»).
            return "✅ ĐÃ LIÊN KẾT THÀNH CÔNG\n" + ZaloBotText.Divider + "\n" +
                   $"👤 {ZaloBotText.Capitalize(name)}\n" +
                   $"🏪 {storeName}\n\n" +
                   (cats.Count > 0
                       ? "Từ giờ bạn nhận qua Zalo:\n" + string.Join("\n", cats.Select(c => "• " + c)) + "\n"
                       : "Từ giờ thông báo của cửa hàng sẽ gửi về đây.\n") +
                   ZaloBotText.Divider + "\n" +
                   "Gửi «HUY» để hủy liên kết.";
        }

        var linked = await db.ZaloBotLinks.AsTracking()
            .Where(l => l.StoreId == s.StoreId && l.ChatId == chatId).ToListAsync(ct);

        if (ZaloBotText.IsUnlinkCommand(text))
        {
            if (linked.Count == 0) return "Zalo này chưa liên kết với ai — không có gì để hủy.";
            foreach (var l in linked)
            {
                l.ChatId = null;
                l.ZaloName = null;
                l.LinkedAt = null;
                l.UpdatedAt = now;
            }
            await db.SaveChangesAsync(ct);
            return "🔕 ĐÃ HỦY LIÊN KẾT\n" + ZaloBotText.Divider + "\n" +
                   $"Bạn đã hủy liên kết — sẽ không nhận thông báo của {storeName} qua Zalo nữa.\n" +
                   "Muốn nhận lại: lấy mã mới rồi gửi vào đây.";
        }

        if (linked.Count > 0)
        {
            var names = new List<string>();
            foreach (var l in linked) names.Add(await PersonNameAsync(l, ct));
            return "ℹ️ ĐANG NHẬN THÔNG BÁO\n" + ZaloBotText.Divider + "\n" +
                   string.Join("\n", names.Select(n => "👤 " + ZaloBotText.Capitalize(n))) + "\n" +
                   $"🏪 {storeName}\n" +
                   ZaloBotText.Divider + "\n" +
                   "Bot chỉ gửi thông báo, không trả lời tin nhắn. Gửi «HUY» để hủy liên kết.";
        }

        return $"👋 Xin chào! Đây là bot thông báo của {storeName}.\n" + ZaloBotText.Divider + "\n" +
               "Để nhận lương, phiếu phạt, lịch làm… qua Zalo, gửi MÃ 6 SỐ vào đây:\n" +
               "• Có tài khoản app: Cài đặt › Liên kết Zalo › Lấy mã\n" +
               "• Không có tài khoản: xin quản lý phiếu mã";
    }

    /// <summary>«tài khoản Nguyễn A» / «nhân viên Nguyễn A (NV001)».</summary>
    async Task<string> PersonNameAsync(ZaloBotLink link, CancellationToken ct)
    {
        if (link.UserId is Guid userId)
        {
            var u = await db.Users.Where(x => x.Id == userId)
                .Select(x => new { x.FirstName, x.LastName, x.UserName }).FirstOrDefaultAsync(ct);
            var full = $"{u?.FirstName} {u?.LastName}".Trim();
            if (full.Length > 0 || u?.UserName != null) return $"tài khoản {(full.Length > 0 ? full : u!.UserName)}";
        }
        if (link.EmployeeId is Guid employeeId)
        {
            var e = await db.Employees.Where(x => x.Id == employeeId)
                .Select(x => new { x.FirstName, x.LastName, x.EmployeeCode }).FirstOrDefaultAsync(ct);
            if (e != null)
            {
                var full = $"{e.FirstName} {e.LastName}".Trim();
                return string.IsNullOrWhiteSpace(e.EmployeeCode) ? $"nhân viên {full}" : $"nhân viên {full} ({e.EmployeeCode})";
            }
        }
        return "tài khoản của bạn";
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
                .Where(l => l.StoreId == group.Key && l.UserId != null && userIds.Contains(l.UserId.Value) && l.ChatId != null)
                .ToDictionaryAsync(l => l.UserId!.Value, l => l.ChatId!, ct);
            if (chats.Count < userIds.Count)
            {
                // Liên kết từ bảng mã trước khi nhân viên có tài khoản: dòng chỉ có EmployeeId.
                var missing = userIds.Where(u => !chats.ContainsKey(u)).ToList();
                var storeId = group.Key;
                var byEmployee = await (from l in db.ZaloBotLinks
                                        join e in db.Employees on l.EmployeeId equals e.Id
                                        where l.StoreId == storeId && l.ChatId != null && e.ApplicationUserId != null
                                              && missing.Contains(e.ApplicationUserId.Value)
                                        select new { UserId = e.ApplicationUserId!.Value, l.ChatId }).ToListAsync(ct);
                foreach (var x in byEmployee) chats.TryAdd(x.UserId, x.ChatId!);
            }
            if (chats.Count == 0) continue;
            var storeName = await StoreNameAsync(db, group.Key, ct);
            var linkedUsers = chats.Keys.ToList();
            var people = await PeopleByUserAsync(db, group.Key, linkedUsers, ct);
            foreach (var n in items)
            {
                if (!chats.TryGetValue(n.TargetUserId!.Value, out var chatId)) continue;
                var link = n.RelatedUrl != null && n.RelatedUrl.StartsWith("http", StringComparison.OrdinalIgnoreCase)
                    ? n.RelatedUrl : appLink;
                var cat = NotificationCategoryCodes.Normalize(n.CategoryCode);
                db.ZaloBotMessages.Add(new ZaloBotMessage
                {
                    Id = Guid.NewGuid(),
                    StoreId = group.Key,
                    UserId = n.TargetUserId,
                    ChatId = chatId,
                    Text = ZaloBotText.FormatNotification(n.Title ?? "", n.Message ?? "", s.HideMoney,
                        new ZaloBotText.MessageContext(storeName, people.GetValueOrDefault(n.TargetUserId!.Value), cat,
                            n.Timestamp == default ? DateTime.UtcNow : n.Timestamp, link)),
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

    /// <summary>
    /// Tin cho nhân viên chưa có tài khoản app (không có Notification): gửi thẳng Zalo nếu nhân viên đã liên kết theo
    /// hồ sơ, cửa hàng bật bot và nhóm thông báo được gửi Zalo. Nhân viên đã có tài khoản bị bỏ qua — họ nhận qua
    /// <see cref="EnqueueAsync(ZKTecoDbContext, IReadOnlyCollection{Notification}, string?, CancellationToken)"/>.
    /// </summary>
    public static async Task<int> EnqueueEmployeesAsync(ZKTecoDbContext db, Guid storeId, IReadOnlyCollection<Guid> employeeIds,
        string? categoryCode, string title, string message, string? appLink, CancellationToken ct = default)
    {
        if (employeeIds.Count == 0) return 0;
        var s = await db.ZaloBotSettings.FirstOrDefaultAsync(x => x.StoreId == storeId, ct);
        if (s is not { Enabled: true } || string.IsNullOrEmpty(s.BotTokenEnc)) return 0;
        var cat = NotificationCategoryCodes.Normalize(categoryCode);
        if (cat == null || !ZaloBotText.ParseCategories(s.Categories).Contains(cat)) return 0;

        var ids = employeeIds.Distinct().ToList();
        var targets = await (from l in db.ZaloBotLinks
                             join e in db.Employees on l.EmployeeId equals e.Id
                             where l.StoreId == storeId && l.ChatId != null && ids.Contains(e.Id)
                                   && e.StoreId == storeId && e.ApplicationUserId == null
                             select new { EmployeeId = e.Id, l.ChatId, e.FirstName, e.LastName, e.EmployeeCode }).ToListAsync(ct);
        if (targets.Count == 0) return 0;
        var storeName = await StoreNameAsync(db, storeId, ct);
        var now = DateTime.UtcNow;
        foreach (var t in targets)
        {
            var text = ZaloBotText.FormatNotification(title, message, s.HideMoney,
                new ZaloBotText.MessageContext(storeName, PersonLabel(t.FirstName, t.LastName, t.EmployeeCode), cat, now, appLink,
                    HasAppAccount: false));
            db.ZaloBotMessages.Add(new ZaloBotMessage
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                EmployeeId = t.EmployeeId,
                ChatId = t.ChatId!,
                Text = text,
                CategoryCode = cat,
                Status = Pending,
                NextAttemptAt = DateTime.UtcNow,
            });
        }
        if (targets.Count > 0) await db.SaveChangesAsync(ct);
        return targets.Count;
    }

    static Task<string?> StoreNameAsync(ZKTecoDbContext db, Guid storeId, CancellationToken ct) =>
        db.Stores.Where(x => x.Id == storeId).Select(x => x.Name).FirstOrDefaultAsync(ct);

    /// <summary>«Lê Cường (NV01)» — tên hồ sơ nhân viên kèm mã; không có hồ sơ thì tên tài khoản.</summary>
    static string PersonLabel(string? first, string? last, string? code)
    {
        var name = $"{first} {last}".Trim();
        return string.IsNullOrWhiteSpace(code) ? name : $"{name} ({code.Trim()})";
    }

    static async Task<Dictionary<Guid, string>> PeopleByUserAsync(ZKTecoDbContext db, Guid storeId, List<Guid> userIds, CancellationToken ct)
    {
        var result = new Dictionary<Guid, string>();
        var emps = await db.Employees
            .Where(e => e.StoreId == storeId && e.ApplicationUserId != null && userIds.Contains(e.ApplicationUserId.Value))
            .Select(e => new { UserId = e.ApplicationUserId!.Value, e.FirstName, e.LastName, e.EmployeeCode }).ToListAsync(ct);
        foreach (var e in emps) result.TryAdd(e.UserId, PersonLabel(e.FirstName, e.LastName, e.EmployeeCode));
        var rest = userIds.Where(u => !result.ContainsKey(u)).ToList();
        if (rest.Count > 0)
        {
            var users = await db.Users.Where(u => rest.Contains(u.Id))
                .Select(u => new { u.Id, u.FirstName, u.LastName, u.UserName }).ToListAsync(ct);
            foreach (var u in users)
            {
                var name = $"{u.FirstName} {u.LastName}".Trim();
                result[u.Id] = name.Length > 0 ? name : u.UserName ?? "";
            }
        }
        return result;
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

    /// <summary>Tin Zalo cho nhân viên chưa có tài khoản app (xem <see cref="ZaloBotService.EnqueueEmployeesAsync"/>).</summary>
    Task EnqueueEmployeesAsync(Guid storeId, IReadOnlyCollection<Guid> employeeIds, string? categoryCode, string title, string message);
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

    public async Task EnqueueEmployeesAsync(Guid storeId, IReadOnlyCollection<Guid> employeeIds, string? categoryCode, string title, string message)
    {
        if (employeeIds.Count == 0) return;
        try
        {
            await using var scope = scopes.CreateAsyncScope();
            var db = scope.ServiceProvider.GetRequiredService<ZKTecoDbContext>();
            await ZaloBotService.EnqueueEmployeesAsync(db, storeId, employeeIds, categoryCode, title, message, AppLink(config));
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Zalo bot employee enqueue failed");
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

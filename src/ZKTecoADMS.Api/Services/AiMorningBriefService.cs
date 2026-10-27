using System.Text.Json;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;
using ZKTecoADMS.Api.Hubs;
using ZKTecoADMS.Application.Authorization;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Notifications;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Helpers;
using ZKTecoADMS.Infrastructure.Services.Push;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Tạo dịch vụ Gemini theo khóa của một cửa hàng khi chạy nền (không có phiên đăng nhập): dùng lại
/// <see cref="TenantScopedGeminiAiService"/> với cửa hàng cố định → khóa riêng trước, khóa AI chung SBOX chỉ khi gói có
/// «Dùng AI chung SBOX» (đúng quy tắc của Trợ lý), tự chuyển khóa / model khi hết lượt.
/// </summary>
public interface IAiMorningBriefGemini
{
    IGeminiAiService Create(ZKTecoDbContext db, Guid storeId);
}

public sealed class AiMorningBriefGemini(IConfiguration configuration, ILogger<GeminiAiService> logger) : IAiMorningBriefGemini
{
    public IGeminiAiService Create(ZKTecoDbContext db, Guid storeId) =>
        new TenantScopedGeminiAiService(configuration, logger, db, new FixedStoreTenant(storeId), new HttpContextAccessor());

    sealed class FixedStoreTenant(Guid storeId) : ITenantProvider
    {
        public Guid? StoreId => storeId;
        public bool IsSuperAccess => false;
    }
}

/// <summary>Gửi một bản tin tới một người (lưu thông báo trong app + SignalR + đẩy FCM).</summary>
public interface IAiMorningBriefNotifier
{
    /// <returns>false = người nhận đã tắt nhóm thông báo này.</returns>
    Task<bool> SendAsync(Guid storeId, Guid userId, BriefMessage message, CancellationToken ct);
}

/// <summary>
/// Thông báo trong app giữ toàn văn bản tin; đẩy (FCM) chỉ gửi tóm tắt ≤ 3 dòng. Tôn trọng: nhóm thông báo người dùng
/// đã tắt, gói không có FCM / loại FCM, giờ yên lặng + tắt đẩy (PushNotificationService tự xử lý).
/// </summary>
public sealed class AiMorningBriefNotifier(
    ZKTecoDbContext db,
    IHubContext<AttendanceHub> hub,
    IPushNotificationService push,
    ILogger<AiMorningBriefNotifier> logger) : IAiMorningBriefNotifier
{
    readonly Dictionary<Guid, bool> _canFcm = [];

    public async Task<bool> SendAsync(Guid storeId, Guid userId, BriefMessage message, CancellationToken ct)
    {
        const string category = AiMorningBriefOptions.CategoryCode;
        var off = await db.NotificationPreferences.AsNoTracking()
            .AnyAsync(p => p.UserId == userId && p.CategoryCode == category && !p.IsEnabled
                           && (p.StoreId == null || p.StoreId == storeId), ct);
        if (off) return false;

        var n = new Notification
        {
            Id = Guid.NewGuid(),
            TargetUserId = userId,
            Type = NotificationType.Info,
            Title = message.Title,
            Message = message.FullText,
            Timestamp = DateTime.UtcNow,
            RelatedUrl = AiMorningBriefOptions.ActionUrl,
            RelatedEntityType = AiMorningBriefOptions.EntityType,
            CategoryCode = category,
            StoreId = storeId,
        };
        db.Notifications.Add(n);
        await db.SaveChangesAsync(ct);

        var display = new NotificationPushDisplay(message.Title, message.PushBody, null, "Bản tin sáng");
        try
        {
            await hub.Clients.Group($"user_{userId}").SendAsync("NewNotification", NotificationDtoMapper.ToSignalRPayload(n, display), ct);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            logger.LogWarning(ex, "Morning brief SignalR failed for user {UserId}", userId);
        }

        try
        {
            if (!_canFcm.TryGetValue(storeId, out var can))
                _canFcm[storeId] = can = await StorePackageHelper.CanSendFcmAsync(db, storeId, category, ct);
            if (can)
                await push.PushToUserAsync(userId, message.Title, message.PushBody, AiMorningBriefOptions.ActionUrl,
                    NotificationDtoMapper.ToFcmData(n, display: display), androidTag: category, ct: ct);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            logger.LogWarning(ex, "Morning brief FCM failed for user {UserId}", userId);
        }
        return true;
    }
}

/// <summary>
/// «Bản tin sáng tự động»: mỗi sáng gửi chủ / quản lý doanh thu hôm qua (so với cùng thứ tuần trước, lũy kế tháng),
/// hàng sắp hết, đơn chờ duyệt trong phạm vi, ai đi trễ / vắng, công nợ khách + 1–2 gợi ý do Gemini viết.
/// Mỗi cửa hàng mỗi ngày đúng MỘT lần gọi AI (phần chung của cửa hàng); phần riêng từng người (chờ duyệt, phạm vi
/// nhân sự, mục được xem) ghép thêm không qua AI. AI lỗi / hết lượt → gửi bản chỉ có số liệu.
/// </summary>
public sealed class AiMorningBriefService(
    ZKTecoDbContext db,
    IModulePermissionService permissions,
    IDataScopeService dataScope,
    IAiMorningBriefGemini gemini,
    IAiMorningBriefNotifier notifier,
    IMemoryCache cache,
    ILogger<AiMorningBriefService> logger)
{
    public const string StatusGenerating = "generating";
    public const string StatusGenerated = "generated";
    public const string StatusSending = "sending";
    public const string StatusSent = "sent";

    /// <summary>Dòng «generating» quá lâu (máy chủ chết giữa lúc gọi AI) → cho gửi bản chỉ có số liệu.</summary>
    static readonly TimeSpan StaleGenerating = TimeSpan.FromMinutes(10);

    /// <summary>Giới hạn suy nghĩ của model — gợi ý ngắn, không cần suy luận dài (đỡ tốn quota, nhanh hơn).</summary>
    public const int ThinkingBudget = 256;

    const int MaxOutputTokens = 1024;
    const int MaxProfileChars = 1000;

    public sealed record SendResult(bool Sent, int Recipients, bool AiUsed, string? Skipped);

    public sealed record PreviewResult(string Title, string Text, string PushBody, bool AiUsed, string? AiError, bool AlreadySent);

    sealed record StoreBrief(AiMorningBriefLog Log, AiMorningBriefStoreData Data, List<string> Suggestions);

    // ─── Thiết lập ────────────────────────────────────────────────

    public static AiMorningBriefSetting DefaultSetting(Guid storeId) => new()
    {
        StoreId = storeId, Enabled = false, SendMinute = AiMorningBriefSchedule.DefaultSendMinute,
        Recipients = AiMorningBriefOptions.DefaultRecipients, Sections = AiMorningBriefOptions.DefaultSections,
    };

    public async Task<AiMorningBriefSetting> GetSettingAsync(Guid storeId, CancellationToken ct) =>
        await db.AiMorningBriefSettings.AsNoTracking().FirstOrDefaultAsync(s => s.StoreId == storeId, ct)
        ?? DefaultSetting(storeId);

    /// <summary>Gói dịch vụ của cửa hàng có «Trợ lý AI».</summary>
    public async Task<bool> ModuleAllowedAsync(Guid storeId, CancellationToken ct) =>
        (await StorePackageHelper.ResolveAllowedModulesAsync(db, storeId, ct))
        .Contains(AiMorningBriefOptions.ModuleCode, StringComparer.OrdinalIgnoreCase);

    // ─── Lịch gửi ─────────────────────────────────────────────────

    /// <summary>Cửa hàng đã bật, đến giờ gửi hôm nay (giờ VN) và chưa gửi / chưa có máy khác đang gửi.</summary>
    public async Task<List<Guid>> DueStoreIdsAsync(DateTime utcNow, CancellationToken ct)
    {
        var settings = await db.AiMorningBriefSettings.AsNoTracking()
            .Where(s => s.Enabled)
            .Select(s => new { s.StoreId, s.SendMinute })
            .ToListAsync(ct);
        if (settings.Count == 0) return [];
        var date = AiMorningBriefSchedule.BriefDate(utcNow);
        var ids = settings.Select(s => s.StoreId).ToList();
        var done = (await db.AiMorningBriefLogs.AsNoTracking()
                .Where(l => l.BriefDate == date && ids.Contains(l.StoreId)
                            && (l.Status == StatusSent || l.Status == StatusSending))
                .Select(l => l.StoreId)
                .ToListAsync(ct))
            .ToHashSet();
        var active = (await db.Stores.AsNoTracking()
                .Where(s => ids.Contains(s.Id) && s.IsActive && !s.IsLocked && (s.ExpiryDate == null || s.ExpiryDate > utcNow))
                .Select(s => s.Id)
                .ToListAsync(ct))
            .ToHashSet();
        return settings
            .Where(s => active.Contains(s.StoreId)
                        && AiMorningBriefSchedule.IsDue(s.SendMinute, utcNow, done.Contains(s.StoreId)))
            .Select(s => s.StoreId)
            .Distinct()
            .ToList();
    }

    // ─── Gửi ──────────────────────────────────────────────────────

    public async Task<SendResult> SendStoreAsync(Guid storeId, DateTime utcNow, CancellationToken ct)
    {
        var setting = await db.AiMorningBriefSettings.AsNoTracking().FirstOrDefaultAsync(s => s.StoreId == storeId, ct);
        if (setting is not { Enabled: true }) return new(false, 0, false, "disabled");
        if (!await ModuleAllowedAsync(storeId, ct)) return new(false, 0, false, "no-module");

        var date = AiMorningBriefSchedule.BriefDate(utcNow);
        var sections = AiMorningBriefOptions.Parse(setting.Sections, AiMorningBriefOptions.AllSections);
        var brief = await EnsureStoreBriefAsync(storeId, date, sections, utcNow, ct);
        if (!await ClaimAsync(brief.Log, utcNow, ct)) return new(false, 0, brief.Log.AiUsed, "already");

        var groups = AiMorningBriefOptions.Parse(setting.Recipients, AiMorningBriefOptions.AllRecipients);
        var recipients = await AiMorningBriefCollector.SelectRecipientsAsync(db, permissions, storeId, groups, ct);
        var sent = 0;
        foreach (var r in recipients)
        {
            try
            {
                var msg = await BuildForUserAsync(brief, r.UserId, r.Role, ct);
                if (msg != null && await notifier.SendAsync(storeId, r.UserId, msg, ct)) sent++;
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                logger.LogWarning(ex, "Morning brief: store {StoreId} user {UserId} failed", storeId, r.UserId);
            }
        }

        brief.Log.Status = StatusSent;
        brief.Log.SentAt = utcNow;
        brief.Log.RecipientCount = sent;
        brief.Log.Text = AiMorningBriefFormatter.StoreText(brief.Data, brief.Suggestions);
        brief.Log.UpdatedAt = utcNow;
        await db.SaveChangesAsync(ct);
        logger.LogInformation("Morning brief sent: store {StoreId} → {Count} người, AI {Ai}", storeId, sent, brief.Log.AiUsed);
        return new(true, sent, brief.Log.AiUsed, null);
    }

    /// <summary>Xem trước bản tin hôm nay của chính người hỏi — không gửi. Chỉ gọi AI nếu hôm nay cửa hàng chưa sinh.</summary>
    public async Task<PreviewResult> PreviewAsync(Guid storeId, Guid userId, string role, DateTime utcNow, CancellationToken ct)
    {
        var setting = await GetSettingAsync(storeId, ct);
        var date = AiMorningBriefSchedule.BriefDate(utcNow);
        var sections = AiMorningBriefOptions.Parse(setting.Sections, AiMorningBriefOptions.AllSections);
        var brief = await EnsureStoreBriefAsync(storeId, date, sections, utcNow, ct);
        var msg = await BuildForUserAsync(brief, userId, role, ct);
        var title = AiMorningBriefFormatter.Title(date);
        return msg == null
            ? new(title, "Bản tin không có mục nào bạn được xem (kiểm tra quyền hoặc các mục đã chọn).", "",
                brief.Log.AiUsed, brief.Log.AiError, brief.Log.Status == StatusSent)
            : new(msg.Title, msg.FullText, msg.PushBody, brief.Log.AiUsed, brief.Log.AiError, brief.Log.Status == StatusSent);
    }

    /// <summary>Bản tin của một người nhận theo quyền + phạm vi quản lý.</summary>
    async Task<BriefMessage?> BuildForUserAsync(StoreBrief brief, Guid userId, string role, CancellationToken ct)
    {
        var view = await ViewForAsync(brief.Data, userId, role, ct);
        return AiMorningBriefFormatter.ForRecipient(brief.Data, view, brief.Suggestions);
    }

    internal async Task<BriefRecipientView> ViewForAsync(AiMorningBriefStoreData data, Guid userId, string role, CancellationToken ct)
    {
        var storeId = data.StoreId;
        var isSuper = ModulePermissionDefaults.IsSuperRole(role);
        var perms = await permissions.GetEffectivePermissionsAsync(userId, role, storeId, ct);
        bool View(params string[] modules) => isSuper || modules.Any(m => perms.TryGetValue(m, out var p) && p.CanView);
        var scope = await AiAssistantScope.ResolveAsync(db, dataScope, null, userId, storeId, role, ct);
        var sec = data.Sections;
        var sales = sec.Contains(AiMorningBriefOptions.Sales) && View("PosSalesReport", "PosReportRevenue");
        var stock = sec.Contains(AiMorningBriefOptions.Stock) && View("PosReportStock", "PosProducts");
        var debt = sec.Contains(AiMorningBriefOptions.Debt) && View("PosReportDebt", "PosCustomers");
        var att = sec.Contains(AiMorningBriefOptions.Attendance) && !scope.SelfOnly
                  && AiAssistantQueryTools.CanTeamSnapshot(perms, isSuper, role);
        var approvals = sec.Contains(AiMorningBriefOptions.Approvals)
            ? await AiMorningBriefCollector.ApprovalsAsync(db, storeId, perms, isSuper, scope, ct)
            : null;
        // Gợi ý AI viết từ số liệu cả cửa hàng → chỉ cho người xem được mọi mục đưa vào AI (không lộ dữ liệu ngoài quyền).
        var ai = (!sec.Contains(AiMorningBriefOptions.Sales) || sales)
                 && (!sec.Contains(AiMorningBriefOptions.Stock) || stock)
                 && (!sec.Contains(AiMorningBriefOptions.Debt) || debt)
                 && (!sec.Contains(AiMorningBriefOptions.Attendance) || (att && scope.WholeStore))
                 && (sales || stock || debt || att);
        return new BriefRecipientView
        {
            UserId = userId, Role = role, Sales = sales, Stock = stock, Debt = debt, Attendance = att, Ai = ai,
            Scope = scope, Approvals = approvals,
        };
    }

    // ─── Phần chung của cửa hàng + một lần gọi AI / ngày ──────────

    async Task<StoreBrief> EnsureStoreBriefAsync(
        Guid storeId, DateTime date, IReadOnlyCollection<string> sections, DateTime utcNow, CancellationToken ct)
    {
        var data = await AiMorningBriefCollector.CollectStoreAsync(db, storeId, date, sections, ct);
        var log = await db.AiMorningBriefLogs.AsTracking().FirstOrDefaultAsync(l => l.StoreId == storeId && l.BriefDate == date, ct);
        if (log == null)
        {
            log = new AiMorningBriefLog
            {
                Id = Guid.NewGuid(), StoreId = storeId, BriefDate = date, Status = StatusGenerating,
                Text = AiMorningBriefFormatter.StoreText(data), CreatedAt = utcNow,
            };
            db.AiMorningBriefLogs.Add(log);
            var inserted = true;
            try
            {
                await db.SaveChangesAsync(ct); // khóa duy nhất (StoreId, BriefDate): máy khác đã tạo → không gọi AI lần hai
            }
            catch (DbUpdateException)
            {
                db.Entry(log).State = EntityState.Detached;
                inserted = false;
                log = await db.AiMorningBriefLogs.AsTracking()
                          .FirstOrDefaultAsync(l => l.StoreId == storeId && l.BriefDate == date, ct)
                      ?? throw new InvalidOperationException("Morning brief log missing after conflict");
            }

            if (inserted)
            {
                var (suggestions, error) = await SuggestAsync(storeId, data, ct);
                log.AiText = suggestions.Count > 0 ? string.Join("\n", suggestions) : null;
                log.AiUsed = suggestions.Count > 0;
                log.AiError = error is { Length: > 500 } ? error[..500] : error;
                log.Text = AiMorningBriefFormatter.StoreText(data, suggestions);
                log.Status = StatusGenerated;
                log.UpdatedAt = utcNow;
                await db.SaveChangesAsync(ct);
            }
        }
        var list = (log.AiText ?? "").Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries).ToList();
        return new StoreBrief(log, data, list);
    }

    /// <summary>Chuyển dòng nhật ký sang «sending» nguyên tử — chỉ một máy / một lượt được gửi.</summary>
    async Task<bool> ClaimAsync(AiMorningBriefLog log, DateTime utcNow, CancellationToken ct)
    {
        var from = log.Status;
        if (from is StatusSending or StatusSent) return false;
        if (from == StatusGenerating && utcNow - (log.UpdatedAt ?? log.CreatedAt) < StaleGenerating) return false;
        if (db.Database.ProviderName?.Contains("InMemory", StringComparison.OrdinalIgnoreCase) != true)
        {
            var n = await db.AiMorningBriefLogs.Where(l => l.Id == log.Id && l.Status == from)
                .ExecuteUpdateAsync(s => s.SetProperty(l => l.Status, StatusSending).SetProperty(l => l.UpdatedAt, utcNow), ct);
            if (n == 0) return false;
            log.Status = StatusSending;
            log.UpdatedAt = utcNow;
            return true;
        }
        // CSDL thử nghiệm (InMemory) không hỗ trợ ExecuteUpdate.
        log.Status = StatusSending;
        log.UpdatedAt = utcNow;
        await db.SaveChangesAsync(ct);
        return true;
    }

    const string SuggestSystemPrompt =
        "Bạn là cố vấn vận hành cho chủ cửa hàng nhỏ ở Việt Nam. Đọc bản tin số liệu sáng nay và đưa ra 1–2 gợi ý hành động "
        + "cụ thể cho hôm nay.\nQuy tắc: chỉ dựa trên số liệu được cung cấp, không bịa số; mỗi gợi ý một câu ngắn (tối đa 30 từ), "
        + "bắt đầu bằng động từ; không chào hỏi, không chép lại bản tin. Số liệu bình thường thì gợi ý cách duy trì / tận dụng.\n"
        + "Chỉ trả JSON: {\"suggestions\":[\"...\",\"...\"]}";

    /// <summary>Đúng một lần gọi Gemini. Lỗi / hết lượt / chưa có khóa → danh sách rỗng + lý do (không ném lỗi).</summary>
    async Task<(List<string> Suggestions, string? Error)> SuggestAsync(Guid storeId, AiMorningBriefStoreData data, CancellationToken ct)
    {
        if (data.Sales == null && data.Stock == null && data.Debt == null && data.Attendance == null)
            return ([], null);
        try
        {
            var ai = gemini.Create(db, storeId);
            if (!ai.IsEnabled)
                return ([], TenantScopedGeminiAiService.NotReadyMessage(ai));
            var user = AiMorningBriefFormatter.StoreText(data);
            var profile = await AiAssistantStoreKnowledge.ProfileAsync(db, cache, storeId, ct);
            if (!string.IsNullOrWhiteSpace(profile))
            {
                var p = profile.Trim();
                user += "\n\nHỒ SƠ CỬA HÀNG (chủ cửa hàng viết):\n" + (p.Length > MaxProfileChars ? p[..MaxProfileChars] : p);
            }
            string json;
            using (GeminiAiService.UseJsonThinkingBudget(ThinkingBudget))
                json = await ai.GenerateJsonAsync(SuggestSystemPrompt, user, null, MaxOutputTokens, ct);
            var list = ParseSuggestions(json);
            return list.Count > 0 ? (list, null) : ([], "AI không trả gợi ý");
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            logger.LogWarning(ex, "Morning brief AI failed for store {StoreId} — gửi bản chỉ có số liệu", storeId);
            return ([], ex is AiApiException { IsQuotaError: true } ? "AI đã hết lượt dùng" : ex.Message);
        }
    }

    internal static List<string> ParseSuggestions(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return [];
        try
        {
            using var doc = JsonDocument.Parse(json);
            var root = doc.RootElement;
            var arr = root.ValueKind == JsonValueKind.Array ? root
                : root.ValueKind == JsonValueKind.Object && root.TryGetProperty("suggestions", out var s) ? s : default;
            if (arr.ValueKind != JsonValueKind.Array) return [];
            return arr.EnumerateArray()
                .Where(e => e.ValueKind == JsonValueKind.String)
                .Select(e => Clean(e.GetString()))
                .Where(t => t.Length > 0)
                .Take(2)
                .ToList();
        }
        catch (JsonException)
        {
            return [];
        }

        static string Clean(string? t)
        {
            var x = string.Join(' ', (t ?? "").Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries)).Trim().TrimStart('-', '•', '*', ' ');
            return x.Length > 240 ? x[..240].TrimEnd() + "…" : x;
        }
    }

    // ─── Lịch sử ──────────────────────────────────────────────────

    public sealed record HistoryRow(DateTime BriefDate, string Status, DateTime? SentAt, int RecipientCount, bool AiUsed,
        string? AiError, string Text);

    public async Task<List<HistoryRow>> HistoryAsync(Guid storeId, int take, CancellationToken ct) =>
        await db.AiMorningBriefLogs.AsNoTracking()
            .Where(l => l.StoreId == storeId)
            .OrderByDescending(l => l.BriefDate)
            .Take(Math.Clamp(take, 1, 60))
            .Select(l => new HistoryRow(l.BriefDate, l.Status, l.SentAt, l.RecipientCount, l.AiUsed, l.AiError, l.Text))
            .ToListAsync(ct);
}

using System.Text.RegularExpressions;
using Microsoft.AspNetCore.Authorization;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Application.Services;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Services;
using ZKTecoADMS.Infrastructure.Helpers;
using ZKTecoADMS.Infrastructure.Services.Push;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// Trung tâm thông báo:
///  • Cài đặt đẩy của tôi (bật / tắt đẩy lên điện thoại, giờ yên lặng) + gửi thử.
///  • Quản lý soạn &amp; gửi thông báo cho nhân viên: mẫu thông báo cửa hàng, chọn người nhận, biến {ten}…
/// </summary>
[ApiController]
[Route("api/notification-center")]
public class NotificationCenterController(
    ZKTecoDbContext db,
    ISystemNotificationService notifications,
    IPushNotificationService push,
    IServiceScopeFactory scopeFactory,
    ILogger<NotificationCenterController> logger) : AuthenticatedControllerBase
{
    // ═══════════════════════ Cài đặt đẩy của tôi ═══════════════════════

    public record PushSettingsDto(
        bool PushEnabled, bool QuietEnabled, string QuietStart, string QuietEnd, bool AllowUrgentInQuiet,
        int ActiveDevices, bool InQuietNow, bool StoreAllowsPush);

    public record UpdatePushSettingsRequest(
        bool PushEnabled, bool QuietEnabled, string? QuietStart, string? QuietEnd, bool AllowUrgentInQuiet);

    [HttpGet("settings")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<PushSettingsDto>>> GetSettings()
        => Ok(AppResponse<PushSettingsDto>.Success(await BuildSettingsAsync()));

    [HttpPut("settings")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<PushSettingsDto>>> UpdateSettings([FromBody] UpdatePushSettingsRequest req)
    {
        var start = NotificationQuietRules.Parse(req.QuietStart);
        var end = NotificationQuietRules.Parse(req.QuietEnd);
        if (req.QuietEnabled && (start == null || end == null))
            return Ok(AppResponse<PushSettingsDto>.Fail("Giờ yên lặng không hợp lệ (định dạng HH:mm)."));
        if (req.QuietEnabled && start == end)
            return Ok(AppResponse<PushSettingsDto>.Fail("Giờ bắt đầu và kết thúc yên lặng phải khác nhau."));

        var s = await db.UserNotificationSettings.FirstOrDefaultAsync(x => x.UserId == CurrentUserId);
        if (s == null)
        {
            s = new UserNotificationSetting { UserId = CurrentUserId };
            db.UserNotificationSettings.Add(s);
        }
        s.PushEnabled = req.PushEnabled;
        s.QuietEnabled = req.QuietEnabled;
        if (start != null) s.QuietStartMinute = start.Value;
        if (end != null) s.QuietEndMinute = end.Value;
        s.AllowUrgentInQuiet = req.AllowUrgentInQuiet;
        s.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync();
        return Ok(AppResponse<PushSettingsDto>.Success(await BuildSettingsAsync()));
    }

    /// <summary>Gửi thử 1 thông báo cho chính mình — kiểm tra điện thoại có nhận được không.</summary>
    [HttpPost("test")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<object>>> SendTest()
    {
        var devices = await db.UserDeviceTokens.CountAsync(t => t.UserId == CurrentUserId && !t.IsDisabled);
        await notifications.CreateAndSendAsync(
            targetUserId: CurrentUserId,
            type: NotificationType.Info,
            title: "Thông báo thử",
            message: $"Điện thoại của bạn nhận thông báo bình thường ({DateTime.UtcNow.AddHours(7):HH:mm dd/MM}).",
            categoryCode: "system",
            storeId: CurrentStoreId);
        var settings = await BuildSettingsAsync();
        var hint = devices == 0
            ? "Chưa có điện thoại nào đăng ký nhận thông báo — hãy mở app SBOX trên điện thoại và cho phép thông báo."
            : !settings.StoreAllowsPush
                ? "Gói dịch vụ của cửa hàng chưa bật thông báo đẩy — thông báo chỉ hiện trong app."
                : !settings.PushEnabled
                    ? "Bạn đang tắt đẩy thông báo lên điện thoại."
                    : settings.InQuietNow
                        ? "Đang trong giờ yên lặng — thông báo đến không chuông."
                        : $"Đã gửi tới {devices} thiết bị.";
        return Ok(AppResponse<object>.Success(new { devices, hint }));
    }

    private async Task<PushSettingsDto> BuildSettingsAsync()
    {
        var s = await db.UserNotificationSettings.AsNoTracking().FirstOrDefaultAsync(x => x.UserId == CurrentUserId)
                ?? new UserNotificationSetting { UserId = CurrentUserId };
        var devices = await db.UserDeviceTokens.CountAsync(t => t.UserId == CurrentUserId && !t.IsDisabled);
        var storeAllows = true;
        if (CurrentStoreId is Guid sid)
        {
            try { storeAllows = await StorePackageHelper.CanSendFcmAsync(db, sid, "system"); }
            catch (Exception ex) { logger.LogWarning(ex, "CanSendFcm check failed"); }
        }
        var inQuiet = s.QuietEnabled && NotificationQuietRules.IsInQuiet(
            NotificationQuietRules.VnMinuteOfDay(DateTime.UtcNow), s.QuietStartMinute, s.QuietEndMinute);
        return new PushSettingsDto(s.PushEnabled, s.QuietEnabled,
            NotificationQuietRules.Format(s.QuietStartMinute), NotificationQuietRules.Format(s.QuietEndMinute),
            s.AllowUrgentInQuiet, devices, inQuiet, storeAllows);
    }

    // ═══════════════════════ Mẫu thông báo cửa hàng ═══════════════════════

    public record TemplateDto(
        Guid? Id, string Name, string Title, string Body, string CategoryCode, int Type, int UsageCount,
        DateTime? LastUsedAt, bool BuiltIn);

    public record SaveTemplateRequest(string Name, string Title, string Body, string? CategoryCode, int Type);

    /// <summary>Mẫu có sẵn — cửa hàng dùng ngay, sửa thành mẫu riêng nếu muốn.</summary>
    private static readonly TemplateDto[] BuiltInTemplates =
    [
        new(null, "Nhắc chấm công", "Nhắc chấm công", "Chào {ten}, nhớ chấm công vào / ra ca hôm nay ({ngay}) nhé!", "attendance", 5, 0, null, true),
        new(null, "Họp toàn thể", "Họp nhân viên {ngay}", "Mời {ten} tham dự buổi họp toàn thể lúc [giờ] tại [địa điểm]. Vui lòng có mặt đúng giờ.", "internal_comm", 0, 0, null, true),
        new(null, "Đổi lịch làm việc", "Thay đổi lịch làm việc", "Lịch làm việc tuần này có thay đổi. {ten} vui lòng mở mục Lịch làm việc để xem ca mới.", "shift", 2, 0, null, true),
        new(null, "Nghỉ lễ", "Thông báo nghỉ lễ", "{cuahang} thông báo lịch nghỉ lễ từ [ngày] đến [ngày]. Chúc {ten} kỳ nghỉ vui vẻ!", "hr", 0, 0, null, true),
        new(null, "Đã có bảng lương", "Bảng lương tháng {thang}", "Bảng lương tháng {thang} đã có. {ten} vào mục Phiếu lương để xem chi tiết và phản hồi nếu có sai sót.", "payroll", 1, 0, null, true),
        new(null, "Nhắc nộp giấy tờ", "Nhắc bổ sung hồ sơ", "{ten} vui lòng bổ sung [giấy tờ] cho phòng nhân sự trước ngày [hạn].", "hr", 5, 0, null, true),
        new(null, "Chúc mừng sinh nhật", "Chúc mừng sinh nhật 🎉", "{cuahang} chúc {ten} sinh nhật vui vẻ, nhiều sức khoẻ và thành công!", "internal_comm", 1, 0, null, true),
        new(null, "Cảnh báo khẩn", "Thông báo khẩn", "[Nội dung khẩn]. {ten} vui lòng làm theo hướng dẫn của quản lý.", "internal_comm", 2, 0, null, true),
    ];

    [HttpGet("templates")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("Notification", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<List<TemplateDto>>>> GetTemplates()
    {
        var storeId = RequiredStoreId;
        var mine = await db.StoreNotificationTemplates.AsNoTracking()
            .Where(t => t.StoreId == storeId && t.IsActive)
            .OrderByDescending(t => t.UsageCount).ThenBy(t => t.Name)
            .Select(t => new TemplateDto(t.Id, t.Name, t.Title, t.Body, t.CategoryCode, (int)t.Type, t.UsageCount,
                t.LastUsedAt, false))
            .ToListAsync();
        return Ok(AppResponse<List<TemplateDto>>.Success([.. mine, .. BuiltInTemplates]));
    }

    [HttpPost("templates")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("Notification", ModulePermissionAction.Create)]
    public Task<ActionResult<AppResponse<TemplateDto>>> CreateTemplate([FromBody] SaveTemplateRequest req)
        => SaveTemplateAsync(null, req);

    [HttpPut("templates/{id:guid}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("Notification", ModulePermissionAction.Create)]
    public Task<ActionResult<AppResponse<TemplateDto>>> UpdateTemplate(Guid id, [FromBody] SaveTemplateRequest req)
        => SaveTemplateAsync(id, req);

    [HttpDelete("templates/{id:guid}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("Notification", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<bool>>> DeleteTemplate(Guid id)
    {
        var storeId = RequiredStoreId;
        var t = await db.StoreNotificationTemplates.FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId);
        if (t == null) return Ok(AppResponse<bool>.Fail("Không tìm thấy mẫu"));
        t.IsActive = false;
        await db.SaveChangesAsync();
        return Ok(AppResponse<bool>.Success(true));
    }

    private async Task<ActionResult<AppResponse<TemplateDto>>> SaveTemplateAsync(Guid? id, SaveTemplateRequest req)
    {
        var storeId = RequiredStoreId;
        var name = (req.Name ?? "").Trim();
        var title = (req.Title ?? "").Trim();
        var body = (req.Body ?? "").Trim();
        if (name.Length == 0) name = title;
        if (title.Length == 0 || body.Length == 0)
            return Ok(AppResponse<TemplateDto>.Fail("Mẫu cần có tiêu đề và nội dung."));
        if (title.Length > 200 || body.Length > 2000 || name.Length > 120)
            return Ok(AppResponse<TemplateDto>.Fail("Tiêu đề tối đa 200 ký tự, nội dung tối đa 2000 ký tự."));

        StoreNotificationTemplate? t;
        if (id.HasValue)
        {
            t = await db.StoreNotificationTemplates.FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId && x.IsActive);
            if (t == null) return Ok(AppResponse<TemplateDto>.Fail("Không tìm thấy mẫu"));
        }
        else
        {
            if (await db.StoreNotificationTemplates.CountAsync(x => x.StoreId == storeId && x.IsActive) >= 100)
                return Ok(AppResponse<TemplateDto>.Fail("Tối đa 100 mẫu cho mỗi cửa hàng."));
            t = new StoreNotificationTemplate { Id = Guid.NewGuid(), StoreId = storeId, CreatedByUserId = CurrentUserId };
            db.StoreNotificationTemplates.Add(t);
        }
        t.Name = name;
        t.Title = title;
        t.Body = body;
        t.CategoryCode = NotificationCategoryCodes.Normalize(req.CategoryCode) ?? "internal_comm";
        t.Type = Enum.IsDefined(typeof(NotificationType), req.Type) ? (NotificationType)req.Type : NotificationType.Info;
        await db.SaveChangesAsync();
        return Ok(AppResponse<TemplateDto>.Success(new TemplateDto(t.Id, t.Name, t.Title, t.Body, t.CategoryCode,
            (int)t.Type, t.UsageCount, t.LastUsedAt, false)));
    }

    // ═══════════════════════ Người nhận ═══════════════════════

    public record AudienceEmployeeDto(
        Guid EmployeeId, Guid UserId, string Name, string? Code, string? Department, Guid? DepartmentId,
        string? Position, bool HasApp, Guid? BranchId = null);
    public record AudienceBranchDto(Guid Id, string Name, bool IsHeadquarter, int Count, int WithApp);

    public record AudienceDepartmentDto(string Key, string Name, int Count, int WithApp);

    public record AudienceDto(
        List<AudienceEmployeeDto> Employees, List<AudienceDepartmentDto> Departments, bool StoreAllowsPush,
        string StoreName, List<AudienceBranchDto>? Branches = null);

    /// <summary>Danh sách nhân viên đang làm có tài khoản (nhận được thông báo), nhóm theo phòng ban.</summary>
    [HttpGet("audience")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("Notification", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<AudienceDto>>> GetAudience()
    {
        var storeId = RequiredStoreId;
        var employees = await LoadAudienceAsync(storeId);
        var departments = employees
            .GroupBy(e => e.Department ?? "")
            .Select(g => new AudienceDepartmentDto(g.Key, g.Key.Length == 0 ? "Chưa có phòng ban" : g.Key,
                g.Count(), g.Count(x => x.HasApp)))
            .OrderBy(d => d.Key.Length == 0).ThenBy(d => d.Name)
            .ToList();
        var allows = true;
        try { allows = await StorePackageHelper.CanSendFcmAsync(db, storeId, "internal_comm"); }
        catch (Exception ex) { logger.LogWarning(ex, "CanSendFcm check failed"); }
        var storeName = await db.Stores.AsNoTracking().Where(s => s.Id == storeId).Select(s => s.Name).FirstOrDefaultAsync() ?? "";
        var branchInfos = await BranchStockService.GetStoreBranchesAsync(db, storeId);
        var hq = BranchStockService.ResolveHeadquarter(branchInfos);
        var branches = branchInfos.Where(b => b.IsActive || employees.Any(e => (e.BranchId ?? hq) == b.Id))
            .Select(b => new AudienceBranchDto(b.Id, b.Name, b.IsHeadquarter,
                employees.Count(e => (e.BranchId ?? hq) == b.Id),
                employees.Count(e => (e.BranchId ?? hq) == b.Id && e.HasApp)))
            .ToList();
        return Ok(AppResponse<AudienceDto>.Success(new AudienceDto(employees, departments, allows, storeName,
            branches.Count > 1 ? branches : null)));
    }

    private Task<List<AudienceEmployeeDto>> LoadAudienceAsync(Guid storeId) =>
        ZKTecoADMS.Api.Services.StoreNotificationBroadcast.LoadAudienceAsync(db, storeId);

    // ═══════════════════════ Gửi ═══════════════════════

    public record SendRequest(
        string Title, string Body, string? CategoryCode, int Type,
        string Audience,                     // all | departments | users
        List<string>? Departments, List<Guid>? UserIds,
        Guid? TemplateId, bool DryRun = false,
        List<Guid>? Branches = null, string? Link = null, DateTime? ScheduleAt = null);

    public record SendResultDto(int Recipients, int WithApp, int WithoutApp, bool PushSent, string PreviewTitle,
        string PreviewBody, List<string> SampleNames,
        Guid? BatchId = null, int Delivered = -1, int Skipped = 0, bool Queued = false,
        bool Scheduled = false, DateTime? ScheduledAt = null);

    /// <summary>
    /// Gửi thông báo cho nhân viên. Biến: {ten} tên NV, {cuahang} tên cửa hàng, {ngay} dd/MM/yyyy, {thang} MM/yyyy,
    /// {gio} HH:mm. DryRun = chỉ xem trước số người nhận.
    /// </summary>
    [HttpPost("send")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("Notification", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<SendResultDto>>> Send([FromBody] SendRequest req)
    {
        var storeId = RequiredStoreId;
        var title = (req.Title ?? "").Trim();
        var body = (req.Body ?? "").Trim();
        if (title.Length == 0 || body.Length == 0)
            return Ok(AppResponse<SendResultDto>.Fail("Nhập tiêu đề và nội dung thông báo."));
        if (title.Length > 200 || body.Length > 2000)
            return Ok(AppResponse<SendResultDto>.Fail("Tiêu đề tối đa 200 ký tự, nội dung tối đa 2000 ký tự."));
        if (!req.DryRun && Regex.IsMatch(title + body, @"\[[^\]\{\}]{1,40}\]"))
            return Ok(AppResponse<SendResultDto>.Fail("Còn chỗ trống [...] trong mẫu chưa điền — vui lòng thay bằng nội dung thật."));

        var link = ZKTecoADMS.Api.Services.StoreNotificationBroadcast.NormalizeLink(req.Link, out var linkErr);
        if (linkErr != null) return Ok(AppResponse<SendResultDto>.Fail(linkErr));
        var all = await LoadAudienceAsync(storeId);
        var hqBranch = await ZKTecoADMS.Api.Services.StoreNotificationBroadcast.HeadquarterAsync(db, storeId);
        var targets = ZKTecoADMS.Api.Services.StoreNotificationBroadcast.Select(
            all, req.Audience, req.Departments, req.UserIds, req.Branches, hqBranch);
        if (targets.Count == 0)
            return Ok(AppResponse<SendResultDto>.Fail("Chưa chọn người nhận (hoặc nhân viên chưa có tài khoản đăng nhập)."));
        if (!req.DryRun && targets.Count > 2000)
            return Ok(AppResponse<SendResultDto>.Fail("Tối đa 2.000 người nhận mỗi lần gửi."));

        var storeName = await db.Stores.AsNoTracking().Where(s => s.Id == storeId).Select(s => s.Name).FirstOrDefaultAsync() ?? "";
        var category = NotificationCategoryCodes.Normalize(req.CategoryCode) ?? "internal_comm";
        var type = Enum.IsDefined(typeof(NotificationType), req.Type) ? (NotificationType)req.Type : NotificationType.Info;
        var nowVn = DateTime.UtcNow.AddHours(7);
        var perPerson = HasPersonalVars(title) || HasPersonalVars(body);

        var first = targets[0];
        var result = new SendResultDto(
            targets.Count,
            targets.Count(t => t.HasApp),
            targets.Count(t => !t.HasApp),
            false,
            Render(title, first.Name, storeName, nowVn),
            Render(body, first.Name, storeName, nowVn),
            targets.Take(5).Select(t => t.Name).ToList());
        if (req.DryRun) return Ok(AppResponse<SendResultDto>.Success(result));

        if (req.ScheduleAt is DateTime when)
        {
            var whenUtc = when.Kind == DateTimeKind.Local ? when.ToUniversalTime() : DateTime.SpecifyKind(when, DateTimeKind.Utc);
            if (whenUtc < DateTime.UtcNow.AddMinutes(1))
                return Ok(AppResponse<SendResultDto>.Fail("Giờ hẹn phải sau thời điểm hiện tại ít nhất 1 phút."));
            if (whenUtc > DateTime.UtcNow.AddDays(90))
                return Ok(AppResponse<SendResultDto>.Fail("Chỉ hẹn giờ gửi trong vòng 90 ngày."));
            var pendingCount = await db.StoreScheduledNotifications.CountAsync(x =>
                x.StoreId == storeId && x.Status == ZKTecoADMS.Api.Services.StoreNotificationBroadcast.Pending);
            if (pendingCount >= 50)
                return Ok(AppResponse<SendResultDto>.Fail("Tối đa 50 thông báo hẹn giờ đang chờ — hủy bớt hoặc đợi gửi."));
            var payload = req with { DryRun = false, ScheduleAt = null, Link = link };
            db.StoreScheduledNotifications.Add(new StoreScheduledNotification
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                CreatedByUserId = CurrentUserId,
                SendAt = whenUtc,
                PayloadJson = System.Text.Json.JsonSerializer.Serialize(payload),
                Title = title,
                RecipientCount = targets.Count,
                IsActive = true,
                CreatedBy = CurrentUserEmail,
            });
            await db.SaveChangesAsync();
            return Ok(AppResponse<SendResultDto>.Success(result with { Scheduled = true, ScheduledAt = whenUtc }));
        }

        var batchId = Guid.NewGuid();
        var senderId = CurrentUserId;
        Task DeliverAsync(ISystemNotificationService svc) =>
            ZKTecoADMS.Api.Services.StoreNotificationBroadcast.DeliverAsync(
                svc, targets, type, title, body, category, senderId, storeId, storeName, batchId, link);

        // Gửi nhiều người: đẩy FCM từng máy mất thời gian → chạy nền, trả lời ngay (xem tiến độ ở «Đã gửi»).
        var queued = targets.Count >= 150;
        if (queued)
        {
            _ = Task.Run(async () =>
            {
                try
                {
                    using var scope = scopeFactory.CreateScope();
                    await DeliverAsync(scope.ServiceProvider.GetRequiredService<ISystemNotificationService>());
                }
                catch (Exception ex) { logger.LogError(ex, "Background notification batch {Batch} failed", batchId); }
            });
        }
        else
        {
            await DeliverAsync(notifications);
        }
        var delivered = queued ? -1 : await db.Notifications.CountAsync(n => n.BatchId == batchId);
        var skipped = queued ? 0 : Math.Max(0, targets.Count - delivered);
        if (req.TemplateId is Guid tid)
        {
            await db.StoreNotificationTemplates
                .Where(t => t.Id == tid && t.StoreId == storeId)
                .ExecuteUpdateAsync(s => s
                    .SetProperty(t => t.UsageCount, t => t.UsageCount + 1)
                    .SetProperty(t => t.LastUsedAt, DateTime.UtcNow));
        }

        var pushAllowed = true;
        try { pushAllowed = await StorePackageHelper.CanSendFcmAsync(db, storeId, category); }
        catch { /* chỉ để hiển thị */ }
        logger.LogInformation("Manager {UserId} sent notification '{Title}' to {Count} users (store {StoreId})",
            CurrentUserId, title, targets.Count, storeId);
        return Ok(AppResponse<SendResultDto>.Success(result with
        {
            PushSent = pushAllowed && result.WithApp > 0,
            BatchId = batchId,
            Delivered = delivered,
            Skipped = skipped,
            Queued = queued,
        }));
    }


    // ═══════════════════════ Đã gửi / ai đã đọc ═══════════════════════

    public record SentBatchDto(
        Guid BatchId, string Title, string Body, string? CategoryCode, int Type, DateTime SentAt,
        int Total, int Read, string? SenderName);

    public record SentRecipientDto(Guid UserId, string Name, string? Code, string? Department, bool IsRead, DateTime? ReadAt);

    private IQueryable<Notification> SentScope(Guid storeId) =>
        db.Notifications.AsNoTracking()
            .Where(n => n.StoreId == storeId && n.BatchId != null && (IsAdmin || n.FromUserId == CurrentUserId));

    /// <summary>Các đợt thông báo đã gửi cho nhân viên (mới nhất trước), kèm số người đã đọc.</summary>
    [HttpGet("sent")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("Notification", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<object>>> GetSent([FromQuery] int page = 1, [FromQuery] int pageSize = 20)
    {
        var storeId = RequiredStoreId;
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 5, 50);
        var groups = SentScope(storeId).GroupBy(n => n.BatchId);
        var total = await groups.CountAsync();
        var rows = await groups
            .Select(g => new
            {
                BatchId = g.Key!.Value,
                Title = g.Max(x => x.Title),
                Body = g.Max(x => x.Message),
                Cat = g.Max(x => x.CategoryCode),
                Type = g.Max(x => (int)x.Type),
                At = g.Min(x => x.Timestamp),
                Total = g.Count(),
                Read = g.Count(x => x.IsRead),
                Sender = g.Max(x => x.FromUserId),
            })
            .OrderByDescending(g => g.At)
            .Skip((page - 1) * pageSize).Take(pageSize)
            .ToListAsync();
        var senderIds = rows.Where(r => r.Sender.HasValue).Select(r => r.Sender!.Value).Distinct().ToList();
        var names = await db.Users.AsNoTracking().Where(u => senderIds.Contains(u.Id))
            .Select(u => new { u.Id, Name = (u.LastName + " " + u.FirstName).Trim() })
            .ToDictionaryAsync(u => u.Id, u => u.Name);
        var items = rows.Select(r => new SentBatchDto(
            r.BatchId, r.Title ?? "", r.Body ?? "", r.Cat, r.Type, r.At, r.Total, r.Read,
            r.Sender.HasValue ? names.GetValueOrDefault(r.Sender.Value) : null)).ToList();
        return Ok(AppResponse<object>.Success(new { items, total, page, pageSize }));
    }

    /// <summary>Chi tiết một đợt: từng người đã đọc / chưa đọc.</summary>
    [HttpGet("sent/{batchId:guid}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("Notification", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<object>>> GetSentDetail(Guid batchId)
    {
        var storeId = RequiredStoreId;
        var rows = await SentScope(storeId).Where(n => n.BatchId == batchId)
            .Select(n => new { n.TargetUserId, n.IsRead, n.ReadAt, n.Title, n.Message, n.CategoryCode, n.Timestamp, Type = (int)n.Type })
            .ToListAsync();
        if (rows.Count == 0) return Ok(AppResponse<object>.Fail("Không tìm thấy đợt thông báo"));
        var userIds = rows.Where(r => r.TargetUserId.HasValue).Select(r => r.TargetUserId!.Value).Distinct().ToList();
        var emps = await db.Employees.AsNoTracking()
            .Where(e => e.StoreId == storeId && e.ApplicationUserId != null && userIds.Contains(e.ApplicationUserId.Value))
            .Select(e => new { UserId = e.ApplicationUserId!.Value, Name = (e.LastName + " " + e.FirstName).Trim(), e.EmployeeCode, e.Department })
            .ToListAsync();
        var byUser = emps.GroupBy(e => e.UserId).ToDictionary(g => g.Key, g => g.First());
        var recipients = rows.Where(r => r.TargetUserId.HasValue).Select(r =>
        {
            byUser.TryGetValue(r.TargetUserId!.Value, out var e);
            return new SentRecipientDto(r.TargetUserId.Value, e?.Name ?? "(không rõ)", e?.EmployeeCode, e?.Department,
                r.IsRead, r.ReadAt);
        }).OrderBy(r => r.IsRead).ThenBy(r => r.Name).ToList();
        var first = rows.OrderBy(r => r.Timestamp).First();
        var recent = await db.Notifications.AsNoTracking().AnyAsync(n =>
            n.StoreId == storeId && n.RelatedEntityType == "NotificationBatchRemind" && n.RelatedEntityId == batchId
            && n.Timestamp > DateTime.UtcNow.AddHours(-2));
        return Ok(AppResponse<object>.Success(new
        {
            batchId,
            title = first.Title ?? "",
            body = first.Message,
            categoryCode = first.CategoryCode,
            type = first.Type,
            sentAt = first.Timestamp,
            total = recipients.Count,
            read = recipients.Count(r => r.IsRead),
            canRemind = !recent && recipients.Any(r => !r.IsRead),
            recipients,
        }));
    }

    /// <summary>Nhắc lại những người chưa đọc (mỗi đợt tối đa 1 lần / 2 giờ).</summary>
    [HttpPost("sent/{batchId:guid}/remind")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("Notification", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<object>>> RemindUnread(Guid batchId)
    {
        var storeId = RequiredStoreId;
        var rows = await SentScope(storeId).Where(n => n.BatchId == batchId)
            .Select(n => new { n.TargetUserId, n.IsRead, n.Title, n.Message, n.CategoryCode, Type = n.Type })
            .ToListAsync();
        if (rows.Count == 0) return Ok(AppResponse<object>.Fail("Không tìm thấy đợt thông báo"));
        var unread = rows.Where(r => !r.IsRead && r.TargetUserId.HasValue).Select(r => r.TargetUserId!.Value).Distinct().ToList();
        if (unread.Count == 0) return Ok(AppResponse<object>.Fail("Mọi người đều đã đọc."));
        var recent = await db.Notifications.AsNoTracking().AnyAsync(n =>
            n.StoreId == storeId && n.RelatedEntityType == "NotificationBatchRemind" && n.RelatedEntityId == batchId
            && n.Timestamp > DateTime.UtcNow.AddHours(-2));
        if (recent) return Ok(AppResponse<object>.Fail("Đã nhắc trong 2 giờ qua — vui lòng đợi thêm."));
        var first = rows[0];
        await notifications.CreateAndSendToUsersAsync(
            unread, first.Type, "Nhắc: " + (first.Title ?? ""), first.Message,
            relatedEntityId: batchId, relatedEntityType: "NotificationBatchRemind",
            fromUserId: CurrentUserId, categoryCode: first.CategoryCode, storeId: storeId);
        return Ok(AppResponse<object>.Success(new { reminded = unread.Count }));
    }


    /// <summary>
    /// Thu hồi một đợt: xóa thông báo của những người CHƯA đọc khỏi trung tâm thông báo của họ.
    /// Người đã đọc giữ nguyên; thông báo đã hiện trên màn hình điện thoại không gỡ được.
    /// </summary>
    [HttpPost("sent/{batchId:guid}/recall")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("Notification", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<object>>> RecallUnread(Guid batchId)
    {
        var storeId = RequiredStoreId;
        var owns = await SentScope(storeId).AnyAsync(n => n.BatchId == batchId);
        if (!owns) return Ok(AppResponse<object>.Fail("Không tìm thấy đợt thông báo"));
        var removed = await db.Notifications
            .Where(n => n.StoreId == storeId && n.BatchId == batchId && !n.IsRead)
            .ExecuteDeleteAsync();
        logger.LogInformation("Manager {UserId} recalled batch {Batch}: {Count} unread removed", CurrentUserId, batchId, removed);
        return Ok(AppResponse<object>.Success(new { recalled = removed }));
    }

    public record ScheduledDto(Guid Id, string Title, DateTime SendAt, int Status, int RecipientCount, string? Error, DateTime? SentAt);

    /// <summary>Thông báo hẹn giờ (chờ gửi + vài lần gần nhất đã xử lý).</summary>
    [HttpGet("scheduled")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("Notification", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<List<ScheduledDto>>>> GetScheduled()
    {
        var storeId = RequiredStoreId;
        var q = db.StoreScheduledNotifications.AsNoTracking()
            .Where(x => x.StoreId == storeId && (IsAdmin || x.CreatedByUserId == CurrentUserId));
        var rows = await q.OrderBy(x => x.Status == 0 ? 0 : 1).ThenBy(x => x.Status == 0 ? x.SendAt : DateTime.MaxValue)
            .ThenByDescending(x => x.SentAt ?? x.SendAt).Take(30)
            .Select(x => new ScheduledDto(x.Id, x.Title ?? "", x.SendAt, x.Status, x.RecipientCount, x.Error, x.SentAt))
            .ToListAsync();
        return Ok(AppResponse<List<ScheduledDto>>.Success(rows));
    }

    [HttpDelete("scheduled/{id:guid}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("Notification", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<bool>>> CancelScheduled(Guid id)
    {
        var storeId = RequiredStoreId;
        var n = await db.StoreScheduledNotifications
            .Where(x => x.Id == id && x.StoreId == storeId && x.Status == ZKTecoADMS.Api.Services.StoreNotificationBroadcast.Pending
                        && (IsAdmin || x.CreatedByUserId == CurrentUserId))
            .ExecuteUpdateAsync(s => s.SetProperty(x => x.Status, ZKTecoADMS.Api.Services.StoreNotificationBroadcast.Cancelled));
        return n == 0
            ? Ok(AppResponse<bool>.Fail("Không hủy được (đã gửi hoặc không tìm thấy)."))
            : Ok(AppResponse<bool>.Success(true));
    }

    private static bool HasPersonalVars(string s) =>
        s.Contains("{ten}", StringComparison.OrdinalIgnoreCase) || s.Contains("{hoten}", StringComparison.OrdinalIgnoreCase);

    /// <summary>Thay biến trong mẫu. Tên rỗng → "bạn".</summary>
    public static string Render(string text, string name, string storeName, DateTime nowVn)
    {
        var firstName = string.IsNullOrWhiteSpace(name) ? "bạn" : name.Trim().Split(' ').Last();
        return Regex.Replace(text, @"\{(ten|hoten|cuahang|ngay|thang|gio)\}", m => m.Groups[1].Value.ToLowerInvariant() switch
        {
            "ten" => firstName,
            "hoten" => string.IsNullOrWhiteSpace(name) ? "bạn" : name.Trim(),
            "cuahang" => storeName,
            "ngay" => nowVn.ToString("dd/MM/yyyy"),
            "thang" => nowVn.ToString("MM/yyyy"),
            "gio" => nowVn.ToString("HH:mm"),
            _ => m.Value,
        }, RegexOptions.IgnoreCase);
    }
}

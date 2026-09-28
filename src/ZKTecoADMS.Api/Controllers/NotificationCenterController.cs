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
        string? Position, bool HasApp);

    public record AudienceDepartmentDto(string Key, string Name, int Count, int WithApp);

    public record AudienceDto(
        List<AudienceEmployeeDto> Employees, List<AudienceDepartmentDto> Departments, bool StoreAllowsPush,
        string StoreName);

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
        return Ok(AppResponse<AudienceDto>.Success(new AudienceDto(employees, departments, allows, storeName)));
    }

    private async Task<List<AudienceEmployeeDto>> LoadAudienceAsync(Guid storeId)
    {
        var rows = await db.Employees.AsNoTracking()
            .Where(e => e.StoreId == storeId && e.ApplicationUserId != null && e.WorkStatus != EmployeeWorkStatus.Resigned)
            .Select(e => new
            {
                e.Id, UserId = e.ApplicationUserId!.Value, Name = (e.LastName + " " + e.FirstName).Trim(),
                e.EmployeeCode, e.Department, e.DepartmentId, e.Position,
            })
            .ToListAsync();
        var userIds = rows.Select(r => r.UserId).ToList();
        var withApp = (await db.UserDeviceTokens.AsNoTracking()
                .Where(t => userIds.Contains(t.UserId) && !t.IsDisabled)
                .Select(t => t.UserId).Distinct().ToListAsync())
            .ToHashSet();
        return rows
            .GroupBy(r => r.UserId).Select(g => g.First())
            .Select(r => new AudienceEmployeeDto(r.Id, r.UserId, r.Name, r.EmployeeCode,
                string.IsNullOrWhiteSpace(r.Department) ? null : r.Department.Trim(), r.DepartmentId, r.Position,
                withApp.Contains(r.UserId)))
            .OrderBy(r => r.Name)
            .ToList();
    }

    // ═══════════════════════ Gửi ═══════════════════════

    public record SendRequest(
        string Title, string Body, string? CategoryCode, int Type,
        string Audience,                     // all | departments | users
        List<string>? Departments, List<Guid>? UserIds,
        Guid? TemplateId, bool DryRun = false);

    public record SendResultDto(int Recipients, int WithApp, int WithoutApp, bool PushSent, string PreviewTitle,
        string PreviewBody, List<string> SampleNames);

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

        var all = await LoadAudienceAsync(storeId);
        List<AudienceEmployeeDto> targets = (req.Audience ?? "all").ToLowerInvariant() switch
        {
            "departments" => all.Where(e => (req.Departments ?? []).Contains(e.Department ?? "")).ToList(),
            "users" => all.Where(e => (req.UserIds ?? []).Contains(e.UserId)).ToList(),
            _ => all,
        };
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

        if (perPerson)
        {
            // Nội dung khác nhau từng người → gửi theo nhóm cùng nội dung (tên trùng nhau gộp chung).
            foreach (var g in targets.GroupBy(t => t.Name))
            {
                await notifications.CreateAndSendToUsersAsync(
                    g.Select(x => x.UserId).ToList(), type,
                    Render(title, g.Key, storeName, nowVn), Render(body, g.Key, storeName, nowVn),
                    fromUserId: CurrentUserId, categoryCode: category, storeId: storeId);
            }
        }
        else
        {
            await notifications.CreateAndSendToUsersAsync(
                targets.Select(t => t.UserId).ToList(), type,
                Render(title, "", storeName, nowVn), Render(body, "", storeName, nowVn),
                fromUserId: CurrentUserId, categoryCode: category, storeId: storeId);
        }

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
        return Ok(AppResponse<SendResultDto>.Success(result with { PushSent = pushAllowed && result.WithApp > 0 }));
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

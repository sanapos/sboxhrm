using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// Zalo bot của cửa hàng (Thiết lập SBOX › Zalo bot): nhập token, chọn nhóm thông báo gửi Zalo, xem ai đã liên kết.
/// Mỗi người tự liên kết Zalo của mình ở Cài đặt (/me). Zalo gọi webhook khi có người nhắn bot.
/// </summary>
[ApiController]
[Route("api/zalo-bot")]
[Authorize]
public class ZaloBotController(
    ZKTecoDbContext db,
    ZaloBotService zalo,
    IZaloBotClient client,
    IConfiguration config,
    ILogger<ZaloBotController> logger) : AuthenticatedControllerBase
{
    public sealed record CategoryDto(string Code, string Label);

    public sealed class SettingsDto
    {
        public bool Enabled { get; set; }
        /// <summary>Đã có token (không bao giờ trả token về).</summary>
        public bool HasToken { get; set; }
        public string? BotName { get; set; }
        public string? BotLink { get; set; }
        public bool WebhookOk { get; set; }
        public string? WebhookUrl { get; set; }
        public List<string> Categories { get; set; } = [];
        public bool HideMoney { get; set; }
        public string? LastError { get; set; }
        public int LinkedCount { get; set; }
        public List<CategoryDto> AllCategories { get; set; } = [];
        public DateTime? UpdatedAt { get; set; }
    }

    public sealed class SaveSettingsRequest
    {
        public bool Enabled { get; set; }
        /// <summary>Token mới; để trống = giữ token cũ.</summary>
        public string? BotToken { get; set; }
        public string? BotLink { get; set; }
        public List<string>? Categories { get; set; }
        public bool HideMoney { get; set; }
    }

    public sealed record LinkRowDto(Guid UserId, string Name, string? UserName, string? Role, bool Linked, string? ZaloName, DateTime? LinkedAt);

    public sealed record MyLinkDto(bool Available, bool Linked, string? ZaloName, DateTime? LinkedAt, string? BotName, string? BotLink);

    public sealed record LinkCodeDto(string Code, DateTime ExpiresAt, string? BotName, string? BotLink);

    string WebhookBaseUrl()
    {
        var baseUrl = config["App:PublicBaseUrl"];
        if (!string.IsNullOrWhiteSpace(baseUrl)) return baseUrl;
        var proto = Request.Headers["X-Forwarded-Proto"].FirstOrDefault() ?? Request.Scheme;
        var host = Request.Headers["X-Forwarded-Host"].FirstOrDefault() ?? Request.Host.ToString();
        return $"{proto}://{host}";
    }

    async Task<SettingsDto> ToDtoAsync(ZaloBotSetting? s, Guid storeId, CancellationToken ct) => new()
    {
        Enabled = s?.Enabled ?? false,
        HasToken = !string.IsNullOrEmpty(s?.BotTokenEnc),
        BotName = s?.BotName,
        BotLink = s?.BotLink,
        WebhookOk = s?.WebhookOk ?? false,
        WebhookUrl = s == null ? null : ZaloBotService.WebhookUrl(WebhookBaseUrl(), s.Id),
        Categories = ZaloBotText.ParseCategories(s?.Categories ?? ZaloBotText.DefaultCategories),
        HideMoney = s?.HideMoney ?? false,
        LastError = s?.LastError,
        LinkedCount = await db.ZaloBotLinks.CountAsync(l => l.StoreId == storeId && l.ChatId != null, ct),
        AllCategories = ZaloBotText.AllCategories.Select(c => new CategoryDto(c.Code, c.Label)).ToList(),
        UpdatedAt = s?.UpdatedAt ?? s?.CreatedAt,
    };

    [HttpGet("settings")]
    [RequireModulePermission("SystemSettings", ModulePermissionAction.View)]
    public async Task<IActionResult> GetSettings(CancellationToken ct)
    {
        var storeId = RequiredStoreId;
        var s = await db.ZaloBotSettings.FirstOrDefaultAsync(x => x.StoreId == storeId, ct);
        return Ok(AppResponse<SettingsDto>.Success(await ToDtoAsync(s, storeId, ct)));
    }

    [HttpPut("settings")]
    [RequireModulePermission("SystemSettings", ModulePermissionAction.Edit)]
    public async Task<IActionResult> SaveSettings([FromBody] SaveSettingsRequest req, CancellationToken ct)
    {
        if (req == null) return BadRequest(AppResponse<SettingsDto>.Fail("Thiếu dữ liệu"));
        var botLink = string.IsNullOrWhiteSpace(req.BotLink) ? null : req.BotLink.Trim();
        if (botLink != null && (!Uri.TryCreate(botLink, UriKind.Absolute, out var uri) || uri.Scheme != Uri.UriSchemeHttps))
            return BadRequest(AppResponse<SettingsDto>.Fail("Link mở bot phải là đường dẫn https://"));
        if (botLink?.Length > 500) return BadRequest(AppResponse<SettingsDto>.Fail("Link mở bot quá dài"));

        var storeId = RequiredStoreId;
        var s = await db.ZaloBotSettings.AsTracking().FirstOrDefaultAsync(x => x.StoreId == storeId, ct);
        if (s == null)
        {
            s = new ZaloBotSetting
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                Categories = ZaloBotText.DefaultCategories,
                CreatedBy = CurrentUserId.ToString(),
            };
            db.ZaloBotSettings.Add(s);
        }
        else
        {
            s.UpdatedAt = DateTime.UtcNow;
            s.UpdatedBy = CurrentUserId.ToString();
        }

        if (!string.IsNullOrWhiteSpace(req.BotToken))
        {
            var err = await zalo.ConnectAsync(s, req.BotToken, WebhookBaseUrl(), ct);
            if (err != null) return BadRequest(AppResponse<SettingsDto>.Fail(err));
        }
        if (req.Enabled && string.IsNullOrEmpty(s.BotTokenEnc))
            return BadRequest(AppResponse<SettingsDto>.Fail("Nhập token bot trước khi bật."));

        s.Enabled = req.Enabled;
        s.BotLink = botLink;
        if (req.Categories != null) s.Categories = ZaloBotText.JoinCategories(req.Categories);
        s.HideMoney = req.HideMoney;
        await db.SaveChangesAsync(ct);
        return Ok(AppResponse<SettingsDto>.Success(await ToDtoAsync(s, storeId, ct)));
    }

    /// <summary>Đăng ký lại webhook (đổi tên miền máy chủ, lần trước lỗi).</summary>
    [HttpPost("settings/webhook")]
    [RequireModulePermission("SystemSettings", ModulePermissionAction.Edit)]
    public async Task<IActionResult> RegisterWebhook(CancellationToken ct)
    {
        var storeId = RequiredStoreId;
        var s = await db.ZaloBotSettings.AsTracking().FirstOrDefaultAsync(x => x.StoreId == storeId, ct);
        var token = s == null ? null : zalo.Token(s);
        if (s == null || token == null) return BadRequest(AppResponse<SettingsDto>.Fail("Chưa nhập token bot."));
        await zalo.RegisterWebhookAsync(s, token, WebhookBaseUrl(), ct);
        s.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync(ct);
        return Ok(AppResponse<SettingsDto>.Success(await ToDtoAsync(s, storeId, ct)));
    }

    /// <summary>Gửi tin thử tới Zalo đã liên kết của chính người bấm.</summary>
    [HttpPost("settings/test")]
    [RequireModulePermission("SystemSettings", ModulePermissionAction.Edit)]
    public async Task<IActionResult> SendTest(CancellationToken ct)
    {
        var storeId = RequiredStoreId;
        var s = await db.ZaloBotSettings.FirstOrDefaultAsync(x => x.StoreId == storeId, ct);
        var token = s == null ? null : zalo.Token(s);
        if (token == null) return BadRequest(AppResponse<bool>.Fail("Chưa nhập token bot."));
        var userId = CurrentUserId;
        var link = await db.ZaloBotLinks.FirstOrDefaultAsync(l => l.StoreId == storeId && l.UserId == userId && l.ChatId != null, ct);
        if (link == null)
        {
            var employeeId = await db.Employees.Where(e => e.StoreId == storeId && e.ApplicationUserId == userId)
                .Select(e => (Guid?)e.Id).FirstOrDefaultAsync(ct);
            if (employeeId != null)
                link = await db.ZaloBotLinks.FirstOrDefaultAsync(l => l.StoreId == storeId && l.EmployeeId == employeeId && l.ChatId != null, ct);
        }
        if (link == null)
            return BadRequest(AppResponse<bool>.Fail("Tài khoản của bạn chưa liên kết Zalo — vào Cài đặt › Liên kết Zalo trước."));
        var storeName = await db.Stores.Where(x => x.Id == storeId).Select(x => x.Name).FirstOrDefaultAsync(ct);
        var r = await client.SendMessageAsync(token, link.ChatId!,
            ZaloBotText.FormatNotification("Tin thử từ SBOX",
                "Zalo bot của cửa hàng đã hoạt động. Thông báo lương, phiếu phạt, lịch làm… sẽ gửi về đây theo mẫu này.", false,
                new ZaloBotText.MessageContext(storeName, null, "system", DateTime.UtcNow, ZaloBotOutbox.AppLink(config))), ct);
        return r.Ok
            ? Ok(AppResponse<bool>.Success(true))
            : BadRequest(AppResponse<bool>.Fail($"Gửi không được: {r.Error}"));
    }

    /// <summary>Tài khoản đang hoạt động của cửa hàng và trạng thái liên kết Zalo.</summary>
    [HttpGet("links")]
    [RequireModulePermission("SystemSettings", ModulePermissionAction.View)]
    public async Task<IActionResult> Links(CancellationToken ct)
    {
        var storeId = RequiredStoreId;
        var users = await db.Users
            .Where(u => u.StoreId == storeId && u.IsActive)
            .Select(u => new { u.Id, u.FirstName, u.LastName, u.UserName, u.Role })
            .ToListAsync(ct);
        var links = (await db.ZaloBotLinks
                .Where(l => l.StoreId == storeId && l.ChatId != null && l.UserId != null)
                .ToListAsync(ct))
            .GroupBy(l => l.UserId!.Value)
            .ToDictionary(g => g.Key, g => g.First());
        var rows = users
            .Select(u =>
            {
                links.TryGetValue(u.Id, out var l);
                var name = $"{u.FirstName} {u.LastName}".Trim();
                return new LinkRowDto(u.Id, name.Length > 0 ? name : u.UserName ?? "", u.UserName, u.Role, l != null, l?.ZaloName, l?.LinkedAt);
            })
            .OrderByDescending(r => r.Linked)
            .ThenBy(r => r.Name)
            .ToList();
        return Ok(AppResponse<List<LinkRowDto>>.Success(rows));
    }

    [HttpDelete("links/{userId:guid}")]
    [RequireModulePermission("SystemSettings", ModulePermissionAction.Edit)]
    public async Task<IActionResult> Unlink(Guid userId, CancellationToken ct) =>
        Ok(AppResponse<bool>.Success(await zalo.UnlinkAsync(RequiredStoreId, userId, ct)));

    // ─── Bảng liên kết cả cửa hàng (nhân viên không cần tài khoản) ───────

    public sealed class EmployeeCodesRequest
    {
        /// <summary>Null / rỗng = mọi nhân viên đang làm chưa liên kết.</summary>
        public List<Guid>? EmployeeIds { get; set; }

        /// <summary>Đổi cả mã còn hạn (mã đã phát trước đó hết dùng được).</summary>
        public bool Renew { get; set; }
    }

    /// <summary>Mọi nhân viên đang làm + trạng thái liên kết Zalo + mã liên kết còn hạn (để in / gửi cho nhân viên).</summary>
    [HttpGet("employee-links")]
    [RequireModulePermission("SystemSettings", ModulePermissionAction.View)]
    public async Task<IActionResult> EmployeeLinks(CancellationToken ct) =>
        Ok(AppResponse<List<ZaloBotService.EmployeeLinkRow>>.Success(
            await zalo.EmployeeLinksAsync(RequiredStoreId, DateTime.UtcNow, ct)));

    /// <summary>Cấp mã liên kết (hạn 7 ngày) cho nhân viên chưa liên kết — trả lại bảng mới.</summary>
    [HttpPost("employee-links/codes")]
    [RequireModulePermission("SystemSettings", ModulePermissionAction.Edit)]
    public async Task<IActionResult> CreateEmployeeCodes([FromBody] EmployeeCodesRequest? req, CancellationToken ct)
    {
        var storeId = RequiredStoreId;
        var s = await db.ZaloBotSettings.FirstOrDefaultAsync(x => x.StoreId == storeId, ct);
        if (s == null || string.IsNullOrEmpty(s.BotTokenEnc))
            return BadRequest(AppResponse<List<ZaloBotService.EmployeeLinkRow>>.Fail("Nhập token bot trước khi tạo mã liên kết."));
        var ids = req?.EmployeeIds is { Count: > 0 } list ? list : null;
        await zalo.CreateEmployeeLinkCodesAsync(storeId, ids, req?.Renew ?? false, CurrentUserId, DateTime.UtcNow, ct);
        return Ok(AppResponse<List<ZaloBotService.EmployeeLinkRow>>.Success(
            await zalo.EmployeeLinksAsync(storeId, DateTime.UtcNow, ct)));
    }

    [HttpDelete("employee-links/{employeeId:guid}")]
    [RequireModulePermission("SystemSettings", ModulePermissionAction.Edit)]
    public async Task<IActionResult> UnlinkEmployee(Guid employeeId, CancellationToken ct) =>
        Ok(AppResponse<bool>.Success(await zalo.UnlinkEmployeeAsync(RequiredStoreId, employeeId, ct)));

    // ─── Của chính mình (Cài đặt) ────────────────────────────────

    [HttpGet("me")]
    public async Task<IActionResult> Me(CancellationToken ct)
    {
        var storeId = RequiredStoreId;
        var userId = CurrentUserId;
        var s = await db.ZaloBotSettings.FirstOrDefaultAsync(x => x.StoreId == storeId, ct);
        var link = await db.ZaloBotLinks.FirstOrDefaultAsync(l => l.StoreId == storeId && l.UserId == userId, ct);
        if (link?.ChatId == null)
        {
            // Đã liên kết bằng bảng mã (theo hồ sơ nhân viên) trước khi có tài khoản.
            var employeeId = await db.Employees.Where(e => e.StoreId == storeId && e.ApplicationUserId == userId)
                .Select(e => (Guid?)e.Id).FirstOrDefaultAsync(ct);
            if (employeeId != null)
                link = await db.ZaloBotLinks.FirstOrDefaultAsync(l => l.StoreId == storeId && l.EmployeeId == employeeId && l.ChatId != null, ct) ?? link;
        }
        var available = s is { Enabled: true } && !string.IsNullOrEmpty(s.BotTokenEnc);
        return Ok(AppResponse<MyLinkDto>.Success(new MyLinkDto(
            available, link?.ChatId != null, link?.ZaloName, link?.LinkedAt, s?.BotName, s?.BotLink)));
    }

    [HttpPost("me/code")]
    public async Task<IActionResult> CreateCode(CancellationToken ct)
    {
        var storeId = RequiredStoreId;
        var s = await db.ZaloBotSettings.FirstOrDefaultAsync(x => x.StoreId == storeId, ct);
        if (s is not { Enabled: true } || string.IsNullOrEmpty(s.BotTokenEnc))
            return BadRequest(AppResponse<LinkCodeDto>.Fail("Cửa hàng chưa bật Zalo bot."));
        var link = await zalo.CreateLinkCodeAsync(storeId, CurrentUserId, DateTime.UtcNow, ct);
        return Ok(AppResponse<LinkCodeDto>.Success(new LinkCodeDto(link.PendingCode!, link.PendingCodeExpiresAt!.Value, s.BotName, s.BotLink)));
    }

    [HttpDelete("me")]
    public async Task<IActionResult> UnlinkMe(CancellationToken ct)
    {
        var storeId = RequiredStoreId;
        if (await zalo.UnlinkAsync(storeId, CurrentUserId, ct)) return Ok(AppResponse<bool>.Success(true));
        var employeeId = await db.Employees.Where(e => e.StoreId == storeId && e.ApplicationUserId == CurrentUserId)
            .Select(e => (Guid?)e.Id).FirstOrDefaultAsync(ct);
        return Ok(AppResponse<bool>.Success(employeeId != null && await zalo.UnlinkEmployeeAsync(storeId, employeeId.Value, ct)));
    }

    // ─── Webhook (Zalo gọi) ──────────────────────────────────────

    [HttpPost("webhook/{settingId:guid}")]
    [AllowAnonymous]
    public async Task<IActionResult> Webhook(Guid settingId, [FromBody] JsonElement payload, CancellationToken ct)
    {
        try
        {
            var secret = Request.Headers["X-Bot-Api-Secret-Token"].FirstOrDefault();
            var status = await zalo.HandleWebhookAsync(settingId, secret, payload, DateTime.UtcNow, ct);
            return status == 200 ? Ok(new { message = "ok" }) : StatusCode(status, new { message = status == 403 ? "Unauthorized" : "Not found" });
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Zalo bot webhook failed for {SettingId}", settingId);
            return Ok(new { message = "error" });
        }
    }
}

using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Application.Authorization;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// «Bản tin sáng tự động» (Thiết lập SBOX › Trợ lý AI): thiết lập theo cửa hàng, xem thử bản tin hôm nay, lịch sử 14 ngày.
/// Sửa / xem thử / lịch sử cần quyền như sửa thiết lập AI (tài khoản toàn quyền hoặc «AIGemini» được sửa).
/// </summary>
[ApiController]
[Route("api/ai/morning-brief")]
[Authorize]
public class AiMorningBriefController(
    ZKTecoDbContext db,
    IModulePermissionService modulePermissionService,
    AiMorningBriefService briefs) : AuthenticatedControllerBase
{
    public sealed class SettingsDto
    {
        public bool Enabled { get; set; }
        /// <summary>Giờ gửi «HH:mm» theo giờ Việt Nam.</summary>
        public string SendTime { get; set; } = "07:00";
        public List<string> Recipients { get; set; } = [];
        public List<string> Sections { get; set; } = [];
        public bool CanEdit { get; set; }
        /// <summary>Gói dịch vụ có «Trợ lý AI» (không có thì không gửi).</summary>
        public bool ModuleAllowed { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    /// <summary>Cùng quy tắc sửa hồ sơ / thiết lập Trợ lý AI.</summary>
    async Task<bool> CanEditAsync(CancellationToken ct)
    {
        var role = CurrentUserRole;
        if (ModulePermissionDefaults.IsSuperRole(role)) return true;
        var perms = await modulePermissionService.GetEffectivePermissionsAsync(CurrentUserId, role, CurrentStoreId, ct);
        return perms.TryGetValue("AIGemini", out var p) && p.CanEdit;
    }

    static SettingsDto ToDto(AiMorningBriefSetting s, bool canEdit, bool moduleAllowed) => new()
    {
        Enabled = s.Enabled,
        SendTime = AiMorningBriefSchedule.Format(s.SendMinute),
        Recipients = AiMorningBriefOptions.Parse(s.Recipients, AiMorningBriefOptions.AllRecipients),
        Sections = AiMorningBriefOptions.Parse(s.Sections, AiMorningBriefOptions.AllSections),
        CanEdit = canEdit,
        ModuleAllowed = moduleAllowed,
        UpdatedAt = s.UpdatedAt ?? (s.Id == Guid.Empty ? null : s.CreatedAt),
    };

    [HttpGet("settings")]
    public async Task<IActionResult> GetSettings(CancellationToken ct)
    {
        var storeId = RequiredStoreId;
        var s = await briefs.GetSettingAsync(storeId, ct);
        return Ok(AppResponse<SettingsDto>.Success(ToDto(s, await CanEditAsync(ct), await briefs.ModuleAllowedAsync(storeId, ct))));
    }

    [HttpPut("settings")]
    public async Task<IActionResult> SaveSettings([FromBody] SettingsDto dto, CancellationToken ct)
    {
        if (!await CanEditAsync(ct))
            return StatusCode(403, AppResponse<SettingsDto>.Fail("Tài khoản không có quyền sửa thiết lập Trợ lý AI."));
        if (dto == null) return BadRequest(AppResponse<SettingsDto>.Fail("Thiếu dữ liệu"));
        if (AiMorningBriefSchedule.Parse(dto.SendTime) is not int minute)
            return BadRequest(AppResponse<SettingsDto>.Fail("Giờ gửi không hợp lệ (HH:mm)."));
        var recipients = AiMorningBriefOptions.Join(dto.Recipients, AiMorningBriefOptions.AllRecipients);
        var sections = AiMorningBriefOptions.Join(dto.Sections, AiMorningBriefOptions.AllSections);
        if (dto.Enabled && recipients.Length == 0)
            return BadRequest(AppResponse<SettingsDto>.Fail("Chọn ít nhất một nhóm người nhận."));
        if (dto.Enabled && sections.Length == 0)
            return BadRequest(AppResponse<SettingsDto>.Fail("Chọn ít nhất một mục trong bản tin."));

        var storeId = RequiredStoreId;
        var row = await db.AiMorningBriefSettings.AsTracking().FirstOrDefaultAsync(s => s.StoreId == storeId, ct);
        if (row == null)
        {
            row = new AiMorningBriefSetting { Id = Guid.NewGuid(), StoreId = storeId, CreatedBy = CurrentUserId.ToString() };
            db.AiMorningBriefSettings.Add(row);
        }
        else
        {
            row.UpdatedAt = DateTime.UtcNow;
            row.UpdatedBy = CurrentUserId.ToString();
        }
        row.Enabled = dto.Enabled;
        row.SendMinute = minute;
        row.Recipients = recipients;
        row.Sections = sections;
        await db.SaveChangesAsync(ct);
        return Ok(AppResponse<SettingsDto>.Success(ToDto(row, true, await briefs.ModuleAllowedAsync(storeId, ct))));
    }

    /// <summary>
    /// Xem thử bản tin hôm nay của chính mình (không gửi). Phần gợi ý AI dùng chung cả ngày: nếu hôm nay chưa sinh thì
    /// lần xem thử này là lượt gọi AI duy nhất của cửa hàng, bản gửi lúc hẹn giờ dùng lại.
    /// </summary>
    [HttpPost("preview")]
    public async Task<IActionResult> Preview(CancellationToken ct)
    {
        if (!await CanEditAsync(ct))
            return StatusCode(403, AppResponse<AiMorningBriefService.PreviewResult>.Fail("Tài khoản không có quyền sửa thiết lập Trợ lý AI."));
        var storeId = RequiredStoreId;
        if (!await briefs.ModuleAllowedAsync(storeId, ct))
            return StatusCode(403, AppResponse<AiMorningBriefService.PreviewResult>.Fail("Gói dịch vụ của cửa hàng chưa có «Trợ lý AI»."));
        var r = await briefs.PreviewAsync(storeId, CurrentUserId, CurrentUserRole, DateTime.UtcNow, ct);
        return Ok(AppResponse<AiMorningBriefService.PreviewResult>.Success(r));
    }

    /// <summary>Bản tin 14 ngày gần nhất (bản cả cửa hàng).</summary>
    [HttpGet("history")]
    public async Task<IActionResult> History([FromQuery] int take = 14, CancellationToken ct = default)
    {
        if (!await CanEditAsync(ct))
            return StatusCode(403, AppResponse<List<AiMorningBriefService.HistoryRow>>.Fail("Tài khoản không có quyền xem lịch sử bản tin."));
        return Ok(AppResponse<List<AiMorningBriefService.HistoryRow>>.Success(await briefs.HistoryAsync(RequiredStoreId, take, ct)));
    }
}

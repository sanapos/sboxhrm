using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Api.Hubs;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Application.Authorization;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Services;

namespace ZKTecoADMS.Api.Controllers;

// ═════════════════ DTO ═════════════════

public class CommChannelDto
{
    public Guid Id { get; set; }
    public string? Key { get; set; }
    public string Name { get; set; } = string.Empty;
    public string? Description { get; set; }
    public string? Icon { get; set; }
    public string? Color { get; set; }
    public int PostPolicy { get; set; }
    public bool RequireApproval { get; set; }
    public Guid? BranchId { get; set; }
    public Guid? DepartmentId { get; set; }
    public int SortOrder { get; set; }
    public bool IsSystem { get; set; }
    public bool CanPost { get; set; }
    public int Unread { get; set; }
}

public class CommPollResultDto
{
    public string Question { get; set; } = string.Empty;
    public bool Multiple { get; set; }
    public bool Anonymous { get; set; }
    public DateTime? ClosesAt { get; set; }
    public bool Closed { get; set; }
    public int TotalVoters { get; set; }
    public List<CommPollOptionResultDto> Options { get; set; } = new();
    public List<string> MyVotes { get; set; } = new();
}

public class CommPollOptionResultDto
{
    public string Id { get; set; } = string.Empty;
    public string Text { get; set; } = string.Empty;
    public int Votes { get; set; }
}

public class CommPostDto
{
    public Guid Id { get; set; }
    public Guid? ChannelId { get; set; }
    public string? ChannelName { get; set; }
    public string? ChannelColor { get; set; }
    public CommunicationType Type { get; set; }
    public string Title { get; set; } = string.Empty;
    public string? Summary { get; set; }
    public string ContentHtml { get; set; } = string.Empty;
    public string? ContentFormat { get; set; }
    public string? ContentDelta { get; set; }
    public string? ThumbnailUrl { get; set; }
    public List<string> Images { get; set; } = new();
    public List<CommAttachment> Attachments { get; set; } = new();
    public CommunicationPriority Priority { get; set; }
    public CommunicationStatus Status { get; set; }
    public Guid AuthorId { get; set; }
    public string? AuthorName { get; set; }
    public string? AuthorAvatar { get; set; }
    public DateTime? PublishedAt { get; set; }
    public DateTime? ScheduledAt { get; set; }
    public DateTime CreatedAt { get; set; }
    public bool IsPinned { get; set; }
    public bool RequireAck { get; set; }
    public DateTime? AckDeadline { get; set; }
    public int Version { get; set; }
    public CommAudience? Audience { get; set; }
    public CommPollResultDto? Poll { get; set; }
    public DateTime? EventAt { get; set; }
    public string? EventLocation { get; set; }
    public bool AllowComments { get; set; }
    public string? Tags { get; set; }
    public bool IsAiGenerated { get; set; }

    public int Views { get; set; }
    public int ReactionTotal { get; set; }
    public Dictionary<string, int> Reactions { get; set; } = new();
    public int Comments { get; set; }
    public int AckCount { get; set; }
    public int AudienceCount { get; set; }

    public bool MyRead { get; set; }
    public bool MyAcked { get; set; }
    public int? MyReaction { get; set; }
    public bool MySaved { get; set; }
    public bool CanEdit { get; set; }
    /// <summary>Người xem có quyền kiểm duyệt (ghim, duyệt, xóa bài người khác)</summary>
    public bool CanModerate { get; set; }
    /// <summary>2 bình luận mới nhất (cũ → mới) để hiện ngay trên bảng tin</summary>
    public List<CommCommentDto> LatestComments { get; set; } = new();
}

public class CommReactorDto
{
    public Guid UserId { get; set; }
    public string Name { get; set; } = string.Empty;
    public string? Avatar { get; set; }
    public int Type { get; set; }
}

public class EditCommCommentDto
{
    public string Content { get; set; } = string.Empty;
}

public class SaveCommPostDto
{
    public Guid? ChannelId { get; set; }
    public CommunicationType? Type { get; set; }
    public string Title { get; set; } = string.Empty;
    public string? Summary { get; set; }
    public string? ContentHtml { get; set; }
    public string? ContentDelta { get; set; }
    public string? ThumbnailUrl { get; set; }
    public List<string>? Images { get; set; }
    public List<CommAttachment>? Attachments { get; set; }
    public CommunicationPriority Priority { get; set; } = CommunicationPriority.Normal;
    public bool RequireAck { get; set; }
    public DateTime? AckDeadline { get; set; }
    public CommAudience? Audience { get; set; }
    public CommPoll? Poll { get; set; }
    public DateTime? EventAt { get; set; }
    public string? EventLocation { get; set; }
    public DateTime? ScheduledAt { get; set; }
    public bool AllowComments { get; set; } = true;
    public string? Tags { get; set; }
    public bool IsPinned { get; set; }
    /// <summary>true = đăng / gửi duyệt; false = lưu nháp</summary>
    public bool Publish { get; set; } = true;
    /// <summary>Cập nhật văn bản thành phiên bản mới — mọi người phải xác nhận lại</summary>
    public bool BumpVersion { get; set; }
    public bool IsAiGenerated { get; set; }
    public string? AiPrompt { get; set; }
    public bool Notify { get; set; } = true;
}

public class CommReadersDto
{
    public int AudienceCount { get; set; }
    public int ReadCount { get; set; }
    public int AckCount { get; set; }
    public List<CommReaderDto> People { get; set; } = new();
}

public class CommReaderDto
{
    public Guid EmployeeId { get; set; }
    public string Name { get; set; } = string.Empty;
    public DateTime? ReadAt { get; set; }
    public DateTime? AckAt { get; set; }
    public bool AckCurrent { get; set; }
}

public class CommCommentDto
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public string? UserName { get; set; }
    public string? Avatar { get; set; }
    public string Content { get; set; } = string.Empty;
    public Guid? ParentCommentId { get; set; }
    public DateTime CreatedAt { get; set; }
    public bool CanDelete { get; set; }
    public bool CanEdit { get; set; }
    public bool Edited { get; set; }
    public DateTime? EditedAt { get; set; }
    public int LikeCount { get; set; }
    public bool MyLiked { get; set; }
    public int ReplyCount { get; set; }
}

public class AddCommCommentDto
{
    public string Content { get; set; } = string.Empty;
    public Guid? ParentCommentId { get; set; }
    public List<Guid>? MentionUserIds { get; set; }
}

public class CommAiDraftDto
{
    public string Title { get; set; } = string.Empty;
    public string Summary { get; set; } = string.Empty;
    /// <summary>[{type: h2|h3|p|bullet|ordered|quote, text}] — chữ có thể chứa **đậm**</summary>
    public List<CommAiBlock> Blocks { get; set; } = new();
    public List<string> KeyPoints { get; set; } = new();
    public List<CommAiFaq> Faq { get; set; } = new();
    public List<string> Tags { get; set; } = new();
    public string? SuggestedChannel { get; set; }
    public bool SuggestRequireAck { get; set; }
}

public class CommAiBlock
{
    public string Type { get; set; } = "p";
    public string Text { get; set; } = string.Empty;
}

public class CommAiFaq
{
    public string Q { get; set; } = string.Empty;
    public string A { get; set; } = string.Empty;
}

public class CommAiWriteDto
{
    /// <summary>write / improve / shorten / expand / fix / summarize / announce</summary>
    public string Action { get; set; } = "write";
    public string? Prompt { get; set; }
    public string? Tone { get; set; }
    public string? ChannelKey { get; set; }
    public string? Title { get; set; }
    public string? CurrentText { get; set; }
}

public class CommAiDocumentResultDto
{
    public List<CommAttachment> Attachments { get; set; } = new();
    public CommAiDraftDto? Draft { get; set; }
    public List<string> Warnings { get; set; } = new();
}

public class CommSidebarDto
{
    public int RequiredPending { get; set; }
    public List<CommPostBriefDto> Required { get; set; } = new();
    public int OpenPolls { get; set; }
    public List<CommPostBriefDto> Events { get; set; } = new();
    public List<CommBirthdayDto> Birthdays { get; set; } = new();
    public int PendingApproval { get; set; }
}

public class CommPostBriefDto
{
    public Guid Id { get; set; }
    public string Title { get; set; } = string.Empty;
    public DateTime? At { get; set; }
    public string? Location { get; set; }
    public DateTime? Deadline { get; set; }
}

public class CommBirthdayDto
{
    public Guid EmployeeId { get; set; }
    public string Name { get; set; } = string.Empty;
    public DateTime Date { get; set; }
    public string? PhotoUrl { get; set; }
}

public class CommInsightsDto
{
    public int Posts30 { get; set; }
    public double AvgReadRate { get; set; }
    public int RequiredPosts { get; set; }
    public int OutstandingAcks { get; set; }
    public List<CommPostStatDto> Posts { get; set; } = new();
}

public class CommPostStatDto
{
    public Guid Id { get; set; }
    public string Title { get; set; } = string.Empty;
    public string? ChannelName { get; set; }
    public DateTime? PublishedAt { get; set; }
    public int Audience { get; set; }
    public int Read { get; set; }
    public int Acked { get; set; }
    public bool RequireAck { get; set; }
    public int Reactions { get; set; }
    public int Comments { get; set; }
}

// ═════════════════ Controller ═════════════════

/// <summary>
/// Truyền thông v2 — mạng xã hội nội bộ: kênh, bảng tin, đính kèm file, xác nhận đã đọc nội quy,
/// bình chọn, bình luận @nhắc tên, AI đọc tài liệu và viết bài.
/// </summary>
[ApiController]
[Route("api/communications/v2")]
[Authorize]
public class CommunicationV2Controller(
    ZKTecoDbContext db,
    IGeminiAiService gemini,
    IFileStorageService storage,
    ISystemNotificationService notifications,
    IModulePermissionService permissions,
    IHubContext<AttendanceHub> hub,
    ILogger<CommunicationV2Controller> logger) : AuthenticatedControllerBase
{
    private const long MaxFileBytes = 20 * 1024 * 1024;
    private const int MaxFilesPerPost = 10;

    // ─── Người xem ───────────────────────────────────────────────

    private CommViewer? _viewer;

    private Task<bool> HasCommAsync(ModulePermissionAction action) =>
        permissions.HasPermissionAsync(CurrentUserId, CurrentUserRole, RequiredStoreId, "Communication", action);

    /// <summary>
    /// Người xem. Kiểm duyệt (ghim / duyệt / sửa, xóa bài người khác) theo quyền Truyền thông «Duyệt» hoặc «Sửa»;
    /// đăng bài theo quyền «Thêm» — không dựa vào tên vai trò.
    /// </summary>
    private async Task<CommViewer> ViewerAsync()
    {
        if (_viewer != null) return _viewer;
        var moderator = ModulePermissionDefaults.IsSuperRole(CurrentUserRole)
                        || await HasCommAsync(ModulePermissionAction.Approve)
                        || await HasCommAsync(ModulePermissionAction.Edit);
        var canCreate = moderator || await HasCommAsync(ModulePermissionAction.Create);
        var emp = await TaskWorkflowHelper.GetEmployeeForUserAsync(db, RequiredStoreId, CurrentUserId);
        var user = await db.Users.AsNoTracking().Where(u => u.Id == CurrentUserId)
            .Select(u => new { u.FirstName, u.LastName, u.UserName }).FirstOrDefaultAsync();
        var name = emp != null
            ? $"{emp.LastName} {emp.FirstName}".Trim()
            : $"{user?.LastName} {user?.FirstName}".Trim();
        if (string.IsNullOrWhiteSpace(name)) name = user?.UserName ?? CurrentUserEmail ?? "—";
        // NV chưa gắn chi nhánh = trụ sở: vẫn thấy kênh / bài gửi cho trụ sở.
        var branchId = emp == null ? null
            : emp.BranchId ?? await ZKTecoADMS.Infrastructure.Services.BranchQueryHelper.HeadquarterIdAsync(db, RequiredStoreId);
        return _viewer = new CommViewer(CurrentUserId, emp?.Id, branchId, emp?.DepartmentId, emp?.Position,
            moderator, name, canCreate);
    }

    private static bool CanPost(CommChannel c, CommViewer v) => CommRules.CanPost(c, v);

    private static string CannotPostMessage(CommChannel c, CommViewer v) => v.CanCreate
        ? $"Chỉ người kiểm duyệt được đăng vào kênh «{c.Name}»"
        : "Bạn chưa có quyền đăng bài (Phân quyền › Truyền thông › Thêm)";

    /// <summary>Phát sự kiện realtime cho cả cửa hàng — chỉ gửi mã bài; máy khách tự tải lại theo quyền của mình.</summary>
    private async Task BroadcastAsync(string evt, object payload)
    {
        try { await hub.Clients.Group($"store_{RequiredStoreId}").SendAsync(evt, payload); }
        catch (Exception ex) { logger.LogDebug(ex, "Comm broadcast {Event} failed", evt); }
    }

    private Task PostChangedAsync(Guid id, string action, Guid? channelId = null) =>
        BroadcastAsync("CommPostChanged", new { id, action, channelId, by = CurrentUserId });

    private async Task<Dictionary<Guid, CommChannel>> ChannelMapAsync() =>
        (await CommV2Helper.EnsureChannelsAsync(db, RequiredStoreId, CurrentUserEmail)).ToDictionary(c => c.Id);

    /// <summary>Bài người xem được thấy (đã đăng, đúng đối tượng; tác giả thấy cả bài của mình).</summary>
    private bool Visible(InternalCommunication p, CommChannel? ch, CommViewer v, DateTime now)
    {
        if (p.AuthorId == v.UserId) return true;
        if (p.Status != CommunicationStatus.Published) return v.IsManager && p.Status == CommunicationStatus.PendingApproval;
        if (p.ExpiresAt.HasValue && p.ExpiresAt < now && !v.IsManager) return false;
        return CommV2Helper.Matches(CommV2Helper.Audience(p.Audience), ch, v);
    }

    // ─── Kênh ─────────────────────────────────────────────────────

    [HttpGet("channels")]
    [RequireModulePermission("Communication", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<CommChannelDto>>>> Channels()
    {
        var v = await ViewerAsync();
        var map = await ChannelMapAsync();
        var now = DateTime.UtcNow;
        // Chỉ đếm «chưa đọc» trong 90 ngày gần nhất — không quét toàn bộ lịch sử.
        var since = now.AddDays(-90);
        var posts = await db.InternalCommunications.AsNoTracking()
            .Where(p => p.StoreId == RequiredStoreId && p.Status == CommunicationStatus.Published && p.PublishedAt >= since)
            .Select(p => new { p.Id, p.ChannelId, p.Audience, p.AuthorId, p.Status, p.ExpiresAt })
            .ToListAsync();
        var readIds = (await db.CommunicationReads.AsNoTracking()
            .Where(r => r.StoreId == RequiredStoreId && r.UserId == v.UserId && r.FirstViewedAt >= since.AddDays(-30))
            .Select(r => r.CommunicationId).ToListAsync()).ToHashSet();
        var list = new List<CommChannelDto>();
        foreach (var c in map.Values.Where(c => c.IsActive).OrderBy(c => c.SortOrder).ThenBy(c => c.Name))
        {
            if (!v.IsManager && ((c.BranchId != null && c.BranchId != v.BranchId) || (c.DepartmentId != null && c.DepartmentId != v.DepartmentId)))
                continue;
            var unread = posts.Count(p => p.ChannelId == c.Id && p.AuthorId != v.UserId && !readIds.Contains(p.Id) &&
                                          (p.ExpiresAt == null || p.ExpiresAt > now) &&
                                          CommV2Helper.Matches(CommV2Helper.Audience(p.Audience), c, v));
            list.Add(ToChannelDto(c, v, unread));
        }
        return Ok(AppResponse<List<CommChannelDto>>.Success(list));
    }

    private static CommChannelDto ToChannelDto(CommChannel c, CommViewer v, int unread) => new()
    {
        Id = c.Id,
        Key = c.Key,
        Name = c.Name,
        Description = c.Description,
        Icon = c.Icon,
        Color = c.Color,
        PostPolicy = c.PostPolicy,
        RequireApproval = c.RequireApproval,
        BranchId = c.BranchId,
        DepartmentId = c.DepartmentId,
        SortOrder = c.SortOrder,
        IsSystem = c.IsSystem,
        CanPost = CanPost(c, v),
        Unread = unread,
    };

    [HttpPost("channels")]
    [Authorize(Policy = Application.Constants.PolicyNames.AtLeastManager)]
    [RequireModulePermission("Communication", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<CommChannelDto>>> CreateChannel([FromBody] CommChannelDto dto)
    {
        if (string.IsNullOrWhiteSpace(dto.Name)) return Ok(AppResponse<CommChannelDto>.Error("Nhập tên kênh"));
        await ChannelMapAsync();
        var max = await db.CommChannels.Where(c => c.StoreId == RequiredStoreId).Select(c => (int?)c.SortOrder).MaxAsync() ?? 0;
        var c = new CommChannel
        {
            Id = Guid.NewGuid(),
            StoreId = RequiredStoreId,
            Name = dto.Name.Trim(),
            Description = dto.Description,
            Icon = dto.Icon ?? "forum",
            Color = dto.Color ?? "#158DC0",
            PostPolicy = dto.PostPolicy,
            RequireApproval = dto.RequireApproval,
            BranchId = dto.BranchId,
            DepartmentId = dto.DepartmentId,
            SortOrder = max + 10,
            IsActive = true,
            CreatedBy = CurrentUserEmail,
        };
        db.CommChannels.Add(c);
        await db.SaveChangesAsync();
        return Ok(AppResponse<CommChannelDto>.Success(ToChannelDto(c, await ViewerAsync(), 0)));
    }

    [HttpPut("channels/{id:guid}")]
    [Authorize(Policy = Application.Constants.PolicyNames.AtLeastManager)]
    [RequireModulePermission("Communication", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<CommChannelDto>>> UpdateChannel(Guid id, [FromBody] CommChannelDto dto)
    {
        var c = await db.CommChannels.AsTracking().FirstOrDefaultAsync(x => x.Id == id && x.StoreId == RequiredStoreId);
        if (c == null) return Ok(AppResponse<CommChannelDto>.Error("Không tìm thấy kênh"));
        if (string.IsNullOrWhiteSpace(dto.Name)) return Ok(AppResponse<CommChannelDto>.Error("Nhập tên kênh"));
        c.Name = dto.Name.Trim();
        c.Description = dto.Description;
        c.Icon = dto.Icon ?? c.Icon;
        c.Color = dto.Color ?? c.Color;
        c.PostPolicy = dto.PostPolicy;
        c.RequireApproval = dto.RequireApproval;
        c.BranchId = dto.BranchId;
        c.DepartmentId = dto.DepartmentId;
        c.SortOrder = dto.SortOrder;
        c.UpdatedAt = DateTime.Now;
        c.UpdatedBy = CurrentUserEmail;
        await db.SaveChangesAsync();
        return Ok(AppResponse<CommChannelDto>.Success(ToChannelDto(c, await ViewerAsync(), 0)));
    }

    [HttpDelete("channels/{id:guid}")]
    [Authorize(Policy = Application.Constants.PolicyNames.AtLeastManager)]
    [RequireModulePermission("Communication", ModulePermissionAction.Delete)]
    public async Task<ActionResult<AppResponse<bool>>> DeleteChannel(Guid id)
    {
        var c = await db.CommChannels.AsTracking().FirstOrDefaultAsync(x => x.Id == id && x.StoreId == RequiredStoreId);
        if (c == null) return Ok(AppResponse<bool>.Error("Không tìm thấy kênh"));
        if (c.IsSystem) return Ok(AppResponse<bool>.Error("Không xóa được kênh hệ thống — có thể đổi tên hoặc quyền đăng"));
        var feed = await db.CommChannels.AsNoTracking().FirstOrDefaultAsync(x => x.StoreId == RequiredStoreId && x.Key == "feed");
        var posts = await db.InternalCommunications.AsTracking().Where(p => p.ChannelId == id).ToListAsync();
        foreach (var p in posts) p.ChannelId = feed?.Id;
        c.Deleted = DateTime.Now;
        c.DeletedBy = CurrentUserEmail;
        c.IsActive = false;
        await db.SaveChangesAsync();
        return Ok(AppResponse<bool>.Success(true));
    }

    // ─── Bảng tin ─────────────────────────────────────────────────

    /// <summary>
    /// filter: all / required (bắt buộc đọc chưa xác nhận) / saved / mine / pending (chờ duyệt) / events / polls / files
    /// </summary>
    [HttpGet("feed")]
    [RequireModulePermission("Communication", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<PagedResult<CommPostDto>>>> Feed(
        [FromQuery] Guid? channelId = null, [FromQuery] string filter = "all", [FromQuery] string? search = null,
        [FromQuery] int page = 1, [FromQuery] int pageSize = 15,
        [FromQuery] Guid? authorId = null, [FromQuery] string? tag = null)
    {
        pageSize = Math.Clamp(pageSize, 1, 50);
        page = Math.Max(1, page);
        var v = await ViewerAsync();
        var map = await ChannelMapAsync();
        var now = DateTime.UtcNow;
        var q = db.InternalCommunications.AsNoTracking().Where(p => p.StoreId == RequiredStoreId);
        if (channelId.HasValue) q = q.Where(p => p.ChannelId == channelId);
        if (authorId.HasValue) q = q.Where(p => p.AuthorId == authorId);
        if (!string.IsNullOrWhiteSpace(tag))
        {
            var t = $"%{tag.Trim().TrimStart('#')}%";
            q = q.Where(p => p.Tags != null && EF.Functions.ILike(p.Tags, t));
        }
        if (!string.IsNullOrWhiteSpace(search))
        {
            var s = $"%{search.Trim()}%";
            q = q.Where(p => EF.Functions.ILike(p.Title, s) || EF.Functions.ILike(p.Content, s) ||
                             (p.Tags != null && EF.Functions.ILike(p.Tags, s)) || (p.AuthorName != null && EF.Functions.ILike(p.AuthorName, s)));
        }
        switch (filter)
        {
            case "mine":
                q = q.Where(p => p.AuthorId == v.UserId);
                break;
            case "pending":
                q = q.Where(p => p.Status == CommunicationStatus.PendingApproval);
                break;
            case "saved":
                var savedIds = db.CommunicationBookmarks.Where(b => b.UserId == v.UserId).Select(b => b.CommunicationId);
                q = q.Where(p => savedIds.Contains(p.Id) && p.Status == CommunicationStatus.Published);
                break;
            case "events":
                q = q.Where(p => p.EventAt != null && p.Status == CommunicationStatus.Published);
                break;
            case "polls":
                q = q.Where(p => p.Poll != null && p.Status == CommunicationStatus.Published);
                break;
            case "files":
                q = q.Where(p => p.Attachments != null && p.Attachments != "[]" && p.Status == CommunicationStatus.Published);
                break;
            case "required":
                q = q.Where(p => p.RequireAck && p.Status == CommunicationStatus.Published);
                break;
            default:
                q = q.Where(p => p.Status == CommunicationStatus.Published ||
                                 (p.AuthorId == v.UserId && p.Status != CommunicationStatus.Archived));
                break;
        }
        if (filter == "required")
        {
            var acked = db.CommunicationReads.Where(r => r.UserId == v.UserId && r.AcknowledgedAt != null);
            q = q.Where(p => !acked.Any(r => r.CommunicationId == p.Id && r.AckVersion >= p.Version));
        }

        // Sắp xếp trong DB; quyền xem theo đối tượng nhận (JSON) lọc trong bộ nhớ theo từng lô,
        // dừng ngay khi đủ trang hiện tại + 1 bài để biết còn nữa hay không.
        IOrderedQueryable<InternalCommunication> ordered = filter switch
        {
            "events" => q.OrderBy(p => p.EventAt < now ? 1 : 0).ThenBy(p => p.EventAt),
            "all" => q.OrderByDescending(p => p.IsPinned).ThenByDescending(p => p.PublishedAt ?? p.CreatedAt),
            _ => q.OrderByDescending(p => p.PublishedAt ?? p.CreatedAt),
        };
        var ordered2 = ordered.ThenByDescending(p => p.Id);
        var need = page * pageSize + 1;
        const int batch = 200;
        var visibleIds = new List<Guid>();
        var scanned = 0;
        var exhausted = false;
        while (visibleIds.Count < need)
        {
            var light = await ordered2.Skip(scanned).Take(batch)
                .Select(p => new { p.Id, p.ChannelId, p.Audience, p.AuthorId, p.Status, p.ExpiresAt })
                .ToListAsync();
            scanned += light.Count;
            foreach (var p in light)
            {
                var ch = p.ChannelId.HasValue ? map.GetValueOrDefault(p.ChannelId.Value) : null;
                var post = new InternalCommunication { AuthorId = p.AuthorId, Status = p.Status, ExpiresAt = p.ExpiresAt, Audience = p.Audience };
                if (Visible(post, ch, v, now)) visibleIds.Add(p.Id);
            }
            if (light.Count < batch) { exhausted = true; break; }
            if (scanned >= 5000) break; // chặn quét quá sâu
        }
        var ids = visibleIds.Skip((page - 1) * pageSize).Take(pageSize).ToList();
        var items = await BuildDtosAsync(ids, v, map, withDelta: false);
        var hasMore = visibleIds.Count > page * pageSize;
        return Ok(AppResponse<PagedResult<CommPostDto>>.Success(new PagedResult<CommPostDto>
        {
            Items = items,
            // Hết dữ liệu → tổng chính xác; còn nữa → tối thiểu (đủ để máy khách biết còn trang sau).
            TotalCount = exhausted ? visibleIds.Count : Math.Max(visibleIds.Count, page * pageSize + 1),
            PageNumber = page,
            PageSize = pageSize,
        }));
    }

    private async Task<List<CommPostDto>> BuildDtosAsync(List<Guid> ids, CommViewer v, Dictionary<Guid, CommChannel> map, bool withDelta)
    {
        if (ids.Count == 0) return new();
        var posts = await db.InternalCommunications.AsNoTracking().Where(p => ids.Contains(p.Id)).ToListAsync();
        var reactions = await db.CommunicationReactions.AsNoTracking().Where(r => ids.Contains(r.CommunicationId))
            .Select(r => new { r.CommunicationId, r.UserId, r.ReactionType }).ToListAsync();
        var comments = await db.CommunicationComments.AsNoTracking().Where(c => ids.Contains(c.CommunicationId))
            .GroupBy(c => c.CommunicationId).Select(g => new { g.Key, N = g.Count() }).ToDictionaryAsync(x => x.Key, x => x.N);
        // 2 bình luận gốc mới nhất mỗi bài (hiện ngay dưới bài như mạng xã hội).
        var latestRaw = await db.CommunicationComments.AsNoTracking()
            .Where(c => ids.Contains(c.CommunicationId) && c.ParentCommentId == null &&
                        db.CommunicationComments.Count(o => o.CommunicationId == c.CommunicationId && o.ParentCommentId == null &&
                                                            o.CreatedAt > c.CreatedAt) < 2)
            .ToListAsync();
        var latestDtos = await CommentDtosAsync(latestRaw, v);
        var latestByPost = latestRaw.Zip(latestDtos)
            .GroupBy(x => x.First.CommunicationId)
            .ToDictionary(g => g.Key, g => g.Select(x => x.Second).OrderBy(x => x.CreatedAt).ToList());
        var reads = await db.CommunicationReads.AsNoTracking().Where(r => ids.Contains(r.CommunicationId))
            .Select(r => new { r.CommunicationId, r.UserId, r.AcknowledgedAt, r.AckVersion }).ToListAsync();
        var votes = await db.CommunicationPollVotes.AsNoTracking().Where(x => ids.Contains(x.CommunicationId))
            .Select(x => new { x.CommunicationId, x.UserId, x.OptionId }).ToListAsync();
        var saved = (await db.CommunicationBookmarks.AsNoTracking()
            .Where(b => b.UserId == v.UserId && ids.Contains(b.CommunicationId)).Select(b => b.CommunicationId).ToListAsync()).ToHashSet();
        var authorIds = posts.Select(p => p.AuthorId).Distinct().ToList();
        var avatars = await db.Employees.AsNoTracking()
            .Where(e => e.StoreId == RequiredStoreId && e.ApplicationUserId != null && authorIds.Contains(e.ApplicationUserId.Value))
            .Select(e => new { UserId = e.ApplicationUserId!.Value, e.PhotoUrl })
            .ToListAsync();
        var now = DateTime.UtcNow;

        // Số người nhận — đếm một lần cho mỗi cấu hình đối tượng nhận.
        var audienceCache = new Dictionary<string, int>();
        async Task<int> AudienceCount(InternalCommunication p, CommChannel? ch)
        {
            var key = $"{p.Audience}|{ch?.BranchId}|{ch?.DepartmentId}";
            if (!audienceCache.TryGetValue(key, out var n))
                audienceCache[key] = n = (await CommV2Helper.AudienceEmployeesAsync(db, RequiredStoreId, CommV2Helper.Audience(p.Audience), ch)).Count;
            return n;
        }

        var result = new List<CommPostDto>();
        foreach (var id in ids)
        {
            var p = posts.FirstOrDefault(x => x.Id == id);
            if (p == null) continue;
            var ch = p.ChannelId.HasValue ? map.GetValueOrDefault(p.ChannelId.Value) : null;
            var pr = reactions.Where(r => r.CommunicationId == id).ToList();
            var prd = reads.Where(r => r.CommunicationId == id).ToList();
            var myRead = prd.FirstOrDefault(r => r.UserId == v.UserId);
            var poll = CommV2Helper.Parse<CommPoll>(p.Poll);
            CommPollResultDto? pollDto = null;
            if (poll != null)
            {
                var pv = votes.Where(x => x.CommunicationId == id).ToList();
                pollDto = new CommPollResultDto
                {
                    Question = poll.Question,
                    Multiple = poll.Multiple,
                    Anonymous = poll.Anonymous,
                    ClosesAt = poll.ClosesAt,
                    Closed = poll.ClosesAt.HasValue && poll.ClosesAt < now,
                    TotalVoters = pv.Select(x => x.UserId).Distinct().Count(),
                    Options = poll.Options.Select(o => new CommPollOptionResultDto { Id = o.Id, Text = o.Text, Votes = pv.Count(x => x.OptionId == o.Id) }).ToList(),
                    MyVotes = pv.Where(x => x.UserId == v.UserId).Select(x => x.OptionId).ToList(),
                };
            }
            var legacyText = p.ContentFormat != "html";
            result.Add(new CommPostDto
            {
                Id = p.Id,
                ChannelId = p.ChannelId,
                ChannelName = ch?.Name,
                ChannelColor = ch?.Color,
                Type = p.Type,
                Title = p.Title,
                Summary = p.Summary,
                ContentHtml = legacyText ? System.Net.WebUtility.HtmlEncode(p.Content).Replace("\n", "<br>") : p.Content,
                ContentFormat = p.ContentFormat,
                ContentDelta = withDelta ? p.ContentDelta : null,
                ThumbnailUrl = p.ThumbnailUrl,
                Images = CommV2Helper.Images(p.AttachedImages),
                Attachments = CommV2Helper.Attachments(p.Attachments),
                Priority = p.Priority,
                Status = p.Status,
                AuthorId = p.AuthorId,
                AuthorName = p.AuthorName,
                AuthorAvatar = avatars.FirstOrDefault(a => a.UserId == p.AuthorId)?.PhotoUrl,
                PublishedAt = p.PublishedAt,
                ScheduledAt = p.ScheduledAt,
                CreatedAt = p.CreatedAt,
                IsPinned = p.IsPinned,
                RequireAck = p.RequireAck,
                AckDeadline = p.AckDeadline,
                Version = p.Version,
                Audience = v.IsManager || p.AuthorId == v.UserId ? CommV2Helper.Audience(p.Audience) : null,
                Poll = pollDto,
                EventAt = p.EventAt,
                EventLocation = p.EventLocation,
                AllowComments = p.AllowComments,
                Tags = p.Tags,
                IsAiGenerated = p.IsAiGenerated,
                Views = Math.Max(p.ViewCount, prd.Count),
                ReactionTotal = pr.Count,
                Reactions = pr.GroupBy(r => ((int)r.ReactionType).ToString()).ToDictionary(g => g.Key, g => g.Count()),
                Comments = comments.GetValueOrDefault(id),
                AckCount = prd.Count(r => r.AcknowledgedAt != null && r.AckVersion >= p.Version),
                AudienceCount = await AudienceCount(p, ch),
                MyRead = myRead != null,
                MyAcked = myRead?.AcknowledgedAt != null && myRead.AckVersion >= p.Version,
                MyReaction = pr.Where(r => r.UserId == v.UserId).Select(r => (int?)r.ReactionType).FirstOrDefault(),
                MySaved = saved.Contains(id),
                CanEdit = v.IsManager || p.AuthorId == v.UserId,
                CanModerate = v.IsManager,
                LatestComments = latestByPost.GetValueOrDefault(id) ?? new(),
            });
        }
        return result;
    }

    [HttpGet("posts/{id:guid}")]
    [RequireModulePermission("Communication", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<CommPostDto>>> Get(Guid id, [FromQuery] bool markRead = true)
    {
        var v = await ViewerAsync();
        var map = await ChannelMapAsync();
        var p = await db.InternalCommunications.AsTracking().FirstOrDefaultAsync(x => x.Id == id && x.StoreId == RequiredStoreId);
        if (p == null) return Ok(AppResponse<CommPostDto>.Error("Không tìm thấy bài viết"));
        var ch = p.ChannelId.HasValue ? map.GetValueOrDefault(p.ChannelId.Value) : null;
        if (!Visible(p, ch, v, DateTime.UtcNow)) return Ok(AppResponse<CommPostDto>.Error("Bạn không có quyền xem bài này"));
        if (markRead && p.Status == CommunicationStatus.Published)
        {
            var r = await db.CommunicationReads.AsTracking().FirstOrDefaultAsync(x => x.CommunicationId == id && x.UserId == v.UserId);
            if (r == null)
            {
                db.CommunicationReads.Add(new CommunicationRead
                {
                    Id = Guid.NewGuid(),
                    StoreId = RequiredStoreId,
                    CommunicationId = id,
                    UserId = v.UserId,
                    EmployeeId = v.EmployeeId,
                });
            }
            else
            {
                r.LastViewedAt = DateTime.UtcNow;
                r.ViewCount++;
            }
            // Lượt xem bài = số người đã xem — mở lại không cộng thêm.
            if (r == null) p.ViewCount++;
            try { await db.SaveChangesAsync(); }
            catch (DbUpdateException) { db.ChangeTracker.Clear(); /* hai lượt mở cùng lúc — bỏ qua */ }
        }
        var dto = (await BuildDtosAsync(new List<Guid> { id }, v, map, withDelta: true)).First();
        return Ok(AppResponse<CommPostDto>.Success(dto));
    }

    // ─── Đăng / sửa / xóa ─────────────────────────────────────────

    private string? Validate(SaveCommPostDto d)
    {
        if (string.IsNullOrWhiteSpace(d.Title) && string.IsNullOrWhiteSpace(CommV2Helper.HtmlToText(d.ContentHtml)) &&
            (d.Images?.Count ?? 0) == 0 && (d.Attachments?.Count ?? 0) == 0 && d.Poll == null)
            return "Bài viết đang trống";
        if ((d.Attachments?.Count ?? 0) + (d.Images?.Count ?? 0) > MaxFilesPerPost * 2)
            return $"Tối đa {MaxFilesPerPost} tệp và {MaxFilesPerPost} ảnh mỗi bài";
        if (d.Poll != null)
        {
            var opts = d.Poll.Options.Where(o => !string.IsNullOrWhiteSpace(o.Text)).ToList();
            if (string.IsNullOrWhiteSpace(d.Poll.Question) || opts.Count < 2) return "Bình chọn cần câu hỏi và ít nhất 2 lựa chọn";
        }
        foreach (var a in d.Attachments ?? new())
            if (!Uri.TryCreate(a.Url, UriKind.RelativeOrAbsolute, out _) || a.Url.StartsWith("javascript", StringComparison.OrdinalIgnoreCase))
                return "Tệp đính kèm không hợp lệ";
        return null;
    }

    private void Apply(InternalCommunication p, SaveCommPostDto d, CommChannel ch)
    {
        var html = CommV2Helper.SanitizeHtml(d.ContentHtml);
        var text = CommV2Helper.HtmlToText(html);
        p.ChannelId = ch.Id;
        p.Type = d.Type ?? CommV2Helper.TypeForChannelKey(ch.Key);
        p.Title = string.IsNullOrWhiteSpace(d.Title)
            ? (text.Length > 0 ? new string(text.Take(80).ToArray()).Split('\n')[0] : d.Poll?.Question ?? "Bài viết")
            : d.Title.Trim();
        if (p.Title.Length > 500) p.Title = p.Title[..500];
        p.Content = html;
        p.ContentFormat = "html";
        p.ContentDelta = d.ContentDelta;
        var summary = string.IsNullOrWhiteSpace(d.Summary) ? new string(text.Take(280).ToArray()) : d.Summary.Trim();
        p.Summary = summary.Length > 1000 ? summary[..1000] : summary;
        var images = (d.Images ?? new()).Where(u => !string.IsNullOrWhiteSpace(u)).Distinct().Take(MaxFilesPerPost).ToList();
        p.AttachedImages = images.Count == 0 ? null : JsonSerializer.Serialize(images);
        p.ThumbnailUrl = string.IsNullOrWhiteSpace(d.ThumbnailUrl) ? images.FirstOrDefault() : d.ThumbnailUrl;
        var files = (d.Attachments ?? new()).Take(MaxFilesPerPost).ToList();
        foreach (var f in files) f.Kind = CommDocumentReader.KindOf(f.Name);
        p.Attachments = files.Count == 0 ? null : CommV2Helper.Serialize(files);
        p.Priority = d.Priority;
        p.RequireAck = d.RequireAck;
        p.AckDeadline = d.RequireAck ? d.AckDeadline : null;
        p.Audience = d.Audience == null || d.Audience.IsEveryone ? null : CommV2Helper.Serialize(d.Audience);
        if (d.Poll != null)
        {
            var opts = d.Poll.Options.Where(o => !string.IsNullOrWhiteSpace(o.Text)).Take(12).ToList();
            for (var i = 0; i < opts.Count; i++)
                if (string.IsNullOrWhiteSpace(opts[i].Id)) opts[i].Id = $"o{i + 1}";
            d.Poll.Options = opts;
            p.Poll = CommV2Helper.Serialize(d.Poll);
        }
        else
        {
            p.Poll = null;
        }
        p.EventAt = d.EventAt;
        p.EventLocation = d.EventLocation?.Trim();
        p.AllowComments = d.AllowComments;
        p.Tags = d.Tags;
        p.IsAiGenerated = d.IsAiGenerated;
        if (d.AiPrompt != null) p.AiPrompt = d.AiPrompt.Length > 2000 ? d.AiPrompt[..2000] : d.AiPrompt;
    }

    /// <summary>Trạng thái sau khi lưu: nháp / chờ duyệt / hẹn giờ / đã đăng.</summary>
    private static CommunicationStatus TargetStatus(SaveCommPostDto d, CommChannel ch, CommViewer v) =>
        CommRules.TargetStatus(d.Publish, d.ScheduledAt, ch, v, DateTime.UtcNow);

    [HttpPost("posts")]
    [RequireModulePermission("Communication", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<CommPostDto>>> Create([FromBody] SaveCommPostDto d)
    {
        var v = await ViewerAsync();
        var map = await ChannelMapAsync();
        var ch = d.ChannelId.HasValue ? map.GetValueOrDefault(d.ChannelId.Value) : map.Values.FirstOrDefault(c => c.Key == "feed");
        if (ch == null || !ch.IsActive) return Ok(AppResponse<CommPostDto>.Error("Chọn kênh đăng bài"));
        if (!CanPost(ch, v)) return Ok(AppResponse<CommPostDto>.Error(CannotPostMessage(ch, v)));
        var err = Validate(d);
        if (err != null) return Ok(AppResponse<CommPostDto>.Error(err));

        var p = new InternalCommunication
        {
            Id = Guid.NewGuid(),
            StoreId = RequiredStoreId,
            AuthorId = v.UserId,
            AuthorName = v.DisplayName,
            CreatedBy = CurrentUserEmail,
        };
        Apply(p, d, ch);
        if (!v.IsManager)
        {
            p.RequireAck = false;
            p.IsPinned = false;
            p.Audience = null;
        }
        else
        {
            p.IsPinned = d.IsPinned;
        }
        p.Status = TargetStatus(d, ch, v);
        p.ScheduledAt = p.Status == CommunicationStatus.Scheduled ? d.ScheduledAt : null;
        if (p.Status == CommunicationStatus.Published) p.PublishedAt = DateTime.UtcNow;
        db.InternalCommunications.Add(p);
        await db.SaveChangesAsync();

        if (p.Status == CommunicationStatus.Published && d.Notify)
            await NotifyAudienceAsync(p, ch, v.UserId, isUpdate: false);
        if (p.Status == CommunicationStatus.PendingApproval)
            await NotifyManagersAsync(p, $"{v.DisplayName} gửi bài chờ duyệt: {p.Title}");
        if (p.Status is CommunicationStatus.Published or CommunicationStatus.PendingApproval)
            await PostChangedAsync(p.Id, p.Status == CommunicationStatus.Published ? "created" : "pending", p.ChannelId);
        return await Get(p.Id, markRead: false);
    }

    [HttpPut("posts/{id:guid}")]
    [RequireModulePermission("Communication", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<CommPostDto>>> Update(Guid id, [FromBody] SaveCommPostDto d)
    {
        var v = await ViewerAsync();
        var map = await ChannelMapAsync();
        var p = await db.InternalCommunications.AsTracking().FirstOrDefaultAsync(x => x.Id == id && x.StoreId == RequiredStoreId);
        if (p == null) return Ok(AppResponse<CommPostDto>.Error("Không tìm thấy bài viết"));
        if (!v.IsManager && p.AuthorId != v.UserId) return Ok(AppResponse<CommPostDto>.Error("Bạn không sửa được bài của người khác"));
        var ch = d.ChannelId.HasValue ? map.GetValueOrDefault(d.ChannelId.Value) : (p.ChannelId.HasValue ? map.GetValueOrDefault(p.ChannelId.Value) : null);
        if (ch == null || !ch.IsActive) return Ok(AppResponse<CommPostDto>.Error("Chọn kênh đăng bài"));
        // Người kiểm duyệt sửa bài của người khác không cần quyền đăng vào kênh của bài đó.
        var sameChannel = ch.Id == p.ChannelId;
        if (!CanPost(ch, v) && !(v.IsManager || (sameChannel && p.AuthorId == v.UserId && v.CanCreate)))
            return Ok(AppResponse<CommPostDto>.Error(CannotPostMessage(ch, v)));
        if (p.Status == CommunicationStatus.Archived) return Ok(AppResponse<CommPostDto>.Error("Bài đã bị xóa"));
        var err = Validate(d);
        if (err != null) return Ok(AppResponse<CommPostDto>.Error(err));

        var wasPublished = p.Status == CommunicationStatus.Published;
        var oldPollOptions = CommV2Helper.Parse<CommPoll>(p.Poll)?.Options.Select(o => o.Id).ToHashSet() ?? new();
        Apply(p, d, ch);
        if (v.IsManager) p.IsPinned = d.IsPinned;
        else { p.RequireAck = false; p.Audience = null; }

        // Lựa chọn bình chọn bị xóa → xóa phiếu tương ứng.
        var newOptions = CommV2Helper.Parse<CommPoll>(p.Poll)?.Options.Select(o => o.Id).ToHashSet() ?? new();
        var removed = oldPollOptions.Except(newOptions).ToList();
        if (removed.Count > 0)
            db.CommunicationPollVotes.RemoveRange(await db.CommunicationPollVotes.AsTracking()
                .Where(x => x.CommunicationId == id && removed.Contains(x.OptionId)).ToListAsync());

        if (d.BumpVersion && wasPublished) p.Version++;
        var newStatus = CommRules.StatusAfterEdit(p.Status, d.Publish, d.ScheduledAt, ch, v, DateTime.UtcNow);
        var backToReview = wasPublished && newStatus == CommunicationStatus.PendingApproval;
        if (backToReview)
        {
            // Bài đã duyệt bị sửa trong kênh cần duyệt → ẩn khỏi bảng tin cho tới khi duyệt lại.
            p.Status = CommunicationStatus.PendingApproval;
            p.IsPinned = false;
        }
        else if (!wasPublished)
        {
            p.Status = newStatus;
            p.ScheduledAt = p.Status == CommunicationStatus.Scheduled ? d.ScheduledAt : null;
            if (p.Status == CommunicationStatus.Published) p.PublishedAt = DateTime.UtcNow;
        }
        p.UpdatedAt = DateTime.UtcNow;
        p.UpdatedBy = CurrentUserEmail;
        await db.SaveChangesAsync();

        if (p.Status == CommunicationStatus.Published && d.Notify && (!wasPublished || d.BumpVersion))
            await NotifyAudienceAsync(p, ch, v.UserId, isUpdate: wasPublished);
        if (backToReview || (!wasPublished && p.Status == CommunicationStatus.PendingApproval))
            await NotifyManagersAsync(p, backToReview
                ? $"{v.DisplayName} sửa bài đã đăng, cần duyệt lại: {p.Title}"
                : $"{v.DisplayName} gửi bài chờ duyệt: {p.Title}");
        await PostChangedAsync(p.Id, backToReview ? "pending" : wasPublished ? "updated" :
            p.Status == CommunicationStatus.Published ? "created" : "updated", p.ChannelId);
        return await Get(p.Id, markRead: false);
    }

    [HttpDelete("posts/{id:guid}")]
    [RequireModulePermission("Communication", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<bool>>> Delete(Guid id)
    {
        var v = await ViewerAsync();
        var p = await db.InternalCommunications.AsTracking().FirstOrDefaultAsync(x => x.Id == id && x.StoreId == RequiredStoreId);
        if (p == null) return Ok(AppResponse<bool>.Error("Không tìm thấy bài viết"));
        if (!v.IsManager && p.AuthorId != v.UserId) return Ok(AppResponse<bool>.Error("Bạn không xóa được bài của người khác"));
        // Lưu trữ thay vì xóa cứng — giữ lịch sử xác nhận đọc nội quy.
        p.Status = CommunicationStatus.Archived;
        p.IsPinned = false;
        p.UpdatedAt = DateTime.UtcNow;
        p.UpdatedBy = CurrentUserEmail;
        await db.SaveChangesAsync();
        await PostChangedAsync(p.Id, "deleted", p.ChannelId);
        return Ok(AppResponse<bool>.Success(true));
    }

    [HttpPost("posts/{id:guid}/approve")]
    [RequireModulePermission("Communication", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<CommPostDto>>> Approve(Guid id, [FromQuery] bool approve = true)
    {
        if (!(await ViewerAsync()).IsManager)
            return Ok(AppResponse<CommPostDto>.Error("Cần quyền Truyền thông › Duyệt để duyệt bài"));
        var p = await db.InternalCommunications.AsTracking().FirstOrDefaultAsync(x => x.Id == id && x.StoreId == RequiredStoreId);
        if (p == null || p.Status != CommunicationStatus.PendingApproval) return Ok(AppResponse<CommPostDto>.Error("Bài không ở trạng thái chờ duyệt"));
        p.Status = approve ? CommunicationStatus.Published : CommunicationStatus.Rejected;
        if (approve) p.PublishedAt = DateTime.UtcNow;
        await db.SaveChangesAsync();
        try
        {
            await notifications.CreateAndSendAsync(p.AuthorId, approve ? NotificationType.Success : NotificationType.Warning,
                approve ? "Bài viết đã được duyệt" : "Bài viết bị từ chối", p.Title,
                relatedEntityId: p.Id, relatedEntityType: "Communication", fromUserId: CurrentUserId,
                categoryCode: "communication", storeId: RequiredStoreId);
        }
        catch { /* thông báo lỗi không chặn */ }
        if (approve)
        {
            var map = await ChannelMapAsync();
            var ch = p.ChannelId.HasValue ? map.GetValueOrDefault(p.ChannelId.Value) : null;
            await NotifyAudienceAsync(p, ch, p.AuthorId, isUpdate: false);
        }
        await PostChangedAsync(p.Id, approve ? "created" : "rejected", p.ChannelId);
        return await Get(id, markRead: false);
    }

    [HttpPost("posts/{id:guid}/pin")]
    [RequireModulePermission("Communication", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<bool>>> Pin(Guid id, [FromQuery] bool pinned = true)
    {
        if (!(await ViewerAsync()).IsManager)
            return Ok(AppResponse<bool>.Error("Cần quyền Truyền thông › Sửa để ghim bài"));
        var p = await db.InternalCommunications.AsTracking().FirstOrDefaultAsync(x => x.Id == id && x.StoreId == RequiredStoreId);
        if (p == null) return Ok(AppResponse<bool>.Error("Không tìm thấy bài viết"));
        if (pinned && p.Status != CommunicationStatus.Published) return Ok(AppResponse<bool>.Error("Chỉ ghim được bài đã đăng"));
        p.IsPinned = pinned;
        await db.SaveChangesAsync();
        await PostChangedAsync(p.Id, "updated", p.ChannelId);
        return Ok(AppResponse<bool>.Success(pinned));
    }

    // ─── Tương tác ────────────────────────────────────────────────

    private async Task<(InternalCommunication? post, string? error)> VisiblePostAsync(Guid id, CommViewer v, bool tracking = false)
    {
        var q = db.InternalCommunications.Where(x => x.Id == id && x.StoreId == RequiredStoreId);
        var p = tracking ? await q.AsTracking().FirstOrDefaultAsync() : await q.AsNoTracking().FirstOrDefaultAsync();
        if (p == null) return (null, "Không tìm thấy bài viết");
        var map = await ChannelMapAsync();
        var ch = p.ChannelId.HasValue ? map.GetValueOrDefault(p.ChannelId.Value) : null;
        return Visible(p, ch, v, DateTime.UtcNow) ? (p, null) : (null, "Bạn không có quyền xem bài này");
    }

    [HttpPost("posts/{id:guid}/ack")]
    [RequireModulePermission("Communication", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<bool>>> Acknowledge(Guid id)
    {
        var v = await ViewerAsync();
        var (p, err) = await VisiblePostAsync(id, v);
        if (p == null) return Ok(AppResponse<bool>.Error(err!));
        var r = await db.CommunicationReads.AsTracking().FirstOrDefaultAsync(x => x.CommunicationId == id && x.UserId == v.UserId);
        if (r == null)
        {
            r = new CommunicationRead { Id = Guid.NewGuid(), StoreId = RequiredStoreId, CommunicationId = id, UserId = v.UserId, EmployeeId = v.EmployeeId };
            db.CommunicationReads.Add(r);
        }
        r.AcknowledgedAt = DateTime.UtcNow;
        r.AckVersion = p.Version;
        r.EmployeeId ??= v.EmployeeId;
        await db.SaveChangesAsync();
        return Ok(AppResponse<bool>.Success(true));
    }

    [HttpPost("posts/{id:guid}/react")]
    [RequireModulePermission("Communication", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<int?>>> React(Guid id, [FromQuery] int type = 0)
    {
        var v = await ViewerAsync();
        var (p, err) = await VisiblePostAsync(id, v);
        if (p == null) return Ok(AppResponse<int?>.Error(err!));
        if (!Enum.IsDefined(typeof(ReactionType), type)) return Ok(AppResponse<int?>.Error("Cảm xúc không hợp lệ"));
        if (p.Status != CommunicationStatus.Published) return Ok(AppResponse<int?>.Error("Bài chưa được đăng"));
        var existing = await db.CommunicationReactions.AsTracking()
            .Where(r => r.CommunicationId == id && r.UserId == v.UserId).ToListAsync();
        int? mine = null;
        var mineRow = existing.FirstOrDefault();
        // Bấm lại đúng cảm xúc đang chọn = bỏ; chọn cảm xúc khác = đổi (giữ một dòng / người).
        if (mineRow != null && (int)mineRow.ReactionType == type)
        {
            db.CommunicationReactions.RemoveRange(existing);
        }
        else if (mineRow != null)
        {
            mineRow.ReactionType = (ReactionType)type;
            mineRow.UpdatedAt = DateTime.UtcNow;
            db.CommunicationReactions.RemoveRange(existing.Skip(1));
            mine = type;
        }
        else
        {
            db.CommunicationReactions.Add(new CommunicationReaction
            {
                Id = Guid.NewGuid(),
                CommunicationId = id,
                UserId = v.UserId,
                ReactionType = (ReactionType)type,
            });
            mine = type;
        }
        try
        {
            await db.SaveChangesAsync();
        }
        catch (DbUpdateException)
        {
            // Hai lần bấm cùng lúc — chỉ mục duy nhất giữ một dòng; trả về trạng thái hiện tại.
            db.ChangeTracker.Clear();
            mine = await db.CommunicationReactions.AsNoTracking().Where(r => r.CommunicationId == id && r.UserId == v.UserId)
                .Select(r => (int?)r.ReactionType).FirstOrDefaultAsync();
        }
        var total = await db.CommunicationReactions.CountAsync(r => r.CommunicationId == id);
        var post = await db.InternalCommunications.AsTracking().FirstAsync(x => x.Id == id);
        if (post.LikeCount != total) { post.LikeCount = total; await db.SaveChangesAsync(); }
        await BroadcastAsync("CommReactionChanged", new { postId = id, total, by = v.UserId });
        return Ok(AppResponse<int?>.Success(mine));
    }

    [HttpPost("posts/{id:guid}/vote")]
    [RequireModulePermission("Communication", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<bool>>> Vote(Guid id, [FromBody] List<string> optionIds)
    {
        var v = await ViewerAsync();
        var (p, err) = await VisiblePostAsync(id, v);
        if (p == null) return Ok(AppResponse<bool>.Error(err!));
        var poll = CommV2Helper.Parse<CommPoll>(p.Poll);
        if (poll == null) return Ok(AppResponse<bool>.Error("Bài không có bình chọn"));
        if (poll.ClosesAt.HasValue && poll.ClosesAt < DateTime.UtcNow) return Ok(AppResponse<bool>.Error("Bình chọn đã đóng"));
        var valid = optionIds.Where(o => poll.Options.Any(x => x.Id == o)).Distinct().ToList();
        if (!poll.Multiple && valid.Count > 1) valid = valid.Take(1).ToList();
        var existing = await db.CommunicationPollVotes.AsTracking().Where(x => x.CommunicationId == id && x.UserId == v.UserId).ToListAsync();
        db.CommunicationPollVotes.RemoveRange(existing);
        foreach (var o in valid)
            db.CommunicationPollVotes.Add(new CommunicationPollVote { Id = Guid.NewGuid(), StoreId = RequiredStoreId, CommunicationId = id, UserId = v.UserId, OptionId = o });
        await db.SaveChangesAsync();
        return Ok(AppResponse<bool>.Success(true));
    }

    [HttpPost("posts/{id:guid}/save")]
    [RequireModulePermission("Communication", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<bool>>> Save(Guid id)
    {
        var v = await ViewerAsync();
        var (p, err) = await VisiblePostAsync(id, v);
        if (p == null) return Ok(AppResponse<bool>.Error(err!));
        var b = await db.CommunicationBookmarks.AsTracking().FirstOrDefaultAsync(x => x.CommunicationId == id && x.UserId == v.UserId);
        if (b != null)
        {
            db.CommunicationBookmarks.Remove(b);
            await db.SaveChangesAsync();
            return Ok(AppResponse<bool>.Success(false));
        }
        db.CommunicationBookmarks.Add(new CommunicationBookmark { Id = Guid.NewGuid(), StoreId = RequiredStoreId, CommunicationId = id, UserId = v.UserId });
        await db.SaveChangesAsync();
        return Ok(AppResponse<bool>.Success(true));
    }

    // ─── Bình luận ────────────────────────────────────────────────

    [HttpGet("posts/{id:guid}/comments")]
    [RequireModulePermission("Communication", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<CommCommentDto>>>> Comments(Guid id)
    {
        var v = await ViewerAsync();
        var (p, err) = await VisiblePostAsync(id, v);
        if (p == null) return Ok(AppResponse<List<CommCommentDto>>.Error(err!));
        var list = await db.CommunicationComments.AsNoTracking().Where(c => c.CommunicationId == id)
            .OrderBy(c => c.CreatedAt).Take(1000).ToListAsync();
        return Ok(AppResponse<List<CommCommentDto>>.Success(await CommentDtosAsync(list, v)));
    }

    /// <summary>Dựng DTO bình luận: ảnh đại diện, lượt thích, đã sửa, số phản hồi.</summary>
    private async Task<List<CommCommentDto>> CommentDtosAsync(List<CommunicationComment> list, CommViewer v)
    {
        if (list.Count == 0) return new();
        var ids = list.Select(c => c.Id).ToList();
        var userIds = list.Select(c => c.UserId).Distinct().ToList();
        var avatars = await db.Employees.AsNoTracking()
            .Where(e => e.StoreId == RequiredStoreId && e.ApplicationUserId != null && userIds.Contains(e.ApplicationUserId.Value))
            .Select(e => new { UserId = e.ApplicationUserId!.Value, e.PhotoUrl }).ToListAsync();
        var likes = await db.CommunicationCommentLikes.AsNoTracking().Where(l => ids.Contains(l.CommentId))
            .Select(l => new { l.CommentId, l.UserId }).ToListAsync();
        var replies = await db.CommunicationComments.AsNoTracking()
            .Where(c => c.ParentCommentId != null && ids.Contains(c.ParentCommentId.Value))
            .GroupBy(c => c.ParentCommentId!.Value).Select(g => new { g.Key, N = g.Count() })
            .ToDictionaryAsync(x => x.Key, x => x.N);
        return list.Select(c => new CommCommentDto
        {
            Id = c.Id,
            UserId = c.UserId,
            UserName = c.UserName,
            Avatar = avatars.FirstOrDefault(a => a.UserId == c.UserId)?.PhotoUrl,
            Content = c.Content,
            ParentCommentId = c.ParentCommentId,
            CreatedAt = c.CreatedAt,
            CanDelete = v.IsManager || c.UserId == v.UserId,
            CanEdit = c.UserId == v.UserId,
            Edited = c.UpdatedAt.HasValue,
            EditedAt = c.UpdatedAt,
            LikeCount = likes.Count(l => l.CommentId == c.Id),
            MyLiked = likes.Any(l => l.CommentId == c.Id && l.UserId == v.UserId),
            ReplyCount = replies.GetValueOrDefault(c.Id),
        }).ToList();
    }

    [HttpPost("posts/{id:guid}/comments")]
    [RequireModulePermission("Communication", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<CommCommentDto>>> AddComment(Guid id, [FromBody] AddCommCommentDto d)
    {
        var v = await ViewerAsync();
        var (p, err) = await VisiblePostAsync(id, v);
        if (p == null) return Ok(AppResponse<CommCommentDto>.Error(err!));
        if (p.Status != CommunicationStatus.Published) return Ok(AppResponse<CommCommentDto>.Error("Bài chưa được đăng"));
        if (!p.AllowComments) return Ok(AppResponse<CommCommentDto>.Error("Bài viết đã tắt bình luận"));
        var content = d.Content?.Trim() ?? string.Empty;
        if (content.Length == 0) return Ok(AppResponse<CommCommentDto>.Error("Nhập nội dung bình luận"));
        if (content.Length > 2000) content = content[..2000];
        Guid? parentUser = null;
        if (d.ParentCommentId.HasValue)
        {
            var parent = await db.CommunicationComments.AsNoTracking()
                .Where(c => c.Id == d.ParentCommentId && c.CommunicationId == id)
                .Select(c => new { c.UserId, c.ParentCommentId }).FirstOrDefaultAsync();
            if (parent == null) return Ok(AppResponse<CommCommentDto>.Error("Bình luận gốc không tồn tại"));
            parentUser = parent.UserId;
            // Chỉ 2 cấp: trả lời một phản hồi thì gắn vào bình luận gốc.
            if (parent.ParentCommentId.HasValue) d.ParentCommentId = parent.ParentCommentId;
        }
        var comment = new CommunicationComment
        {
            Id = Guid.NewGuid(),
            CommunicationId = id,
            UserId = v.UserId,
            UserName = v.DisplayName,
            Content = content,
            ParentCommentId = d.ParentCommentId,
        };
        db.CommunicationComments.Add(comment);
        await db.SaveChangesAsync();
        await CommentChangedAsync(id, comment.Id, "added");

        // Thông báo: tác giả bài, người được trả lời, người được @nhắc tên (cùng cửa hàng).
        var targets = new Dictionary<Guid, string>();
        if (p.AuthorId != v.UserId) targets[p.AuthorId] = $"{v.DisplayName} bình luận bài «{p.Title}»";
        if (parentUser.HasValue && parentUser != v.UserId) targets[parentUser.Value] = $"{v.DisplayName} trả lời bình luận của bạn";
        if (d.MentionUserIds is { Count: > 0 })
        {
            var ok = await db.Employees.AsNoTracking()
                .Where(e => e.StoreId == RequiredStoreId && e.ApplicationUserId != null && d.MentionUserIds.Contains(e.ApplicationUserId.Value))
                .Select(e => e.ApplicationUserId!.Value).ToListAsync();
            foreach (var u in ok.Where(u => u != v.UserId)) targets[u] = $"{v.DisplayName} nhắc đến bạn trong bài «{p.Title}»";
        }
        foreach (var (uid, msg) in targets)
        {
            try
            {
                await notifications.CreateAndSendAsync(uid, NotificationType.Info, "Truyền thông", msg,
                    relatedEntityId: id, relatedEntityType: "Communication", fromUserId: v.UserId,
                    categoryCode: "communication", storeId: RequiredStoreId);
            }
            catch { /* bỏ qua */ }
        }
        return Ok(AppResponse<CommCommentDto>.Success((await CommentDtosAsync(new() { comment }, v)).First()));
    }

    private async Task CommentChangedAsync(Guid postId, Guid commentId, string action)
    {
        var count = await db.CommunicationComments.CountAsync(c => c.CommunicationId == postId);
        await BroadcastAsync("CommCommentChanged", new { postId, commentId, action, count, by = CurrentUserId });
    }

    [HttpPut("comments/{commentId:guid}")]
    [RequireModulePermission("Communication", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<CommCommentDto>>> EditComment(Guid commentId, [FromBody] EditCommCommentDto d)
    {
        var v = await ViewerAsync();
        var c = await db.CommunicationComments.AsTracking()
            .FirstOrDefaultAsync(x => x.Id == commentId && x.Communication!.StoreId == RequiredStoreId);
        if (c == null) return Ok(AppResponse<CommCommentDto>.Error("Không tìm thấy bình luận"));
        if (c.UserId != v.UserId) return Ok(AppResponse<CommCommentDto>.Error("Chỉ người viết được sửa bình luận"));
        var content = d.Content?.Trim() ?? string.Empty;
        if (content.Length == 0) return Ok(AppResponse<CommCommentDto>.Error("Nhập nội dung bình luận"));
        if (content.Length > 2000) content = content[..2000];
        if (content != c.Content)
        {
            c.Content = content;
            c.UpdatedAt = DateTime.UtcNow;
            c.UpdatedBy = CurrentUserEmail;
            await db.SaveChangesAsync();
            await CommentChangedAsync(c.CommunicationId, c.Id, "edited");
        }
        return Ok(AppResponse<CommCommentDto>.Success((await CommentDtosAsync(new() { c }, v)).First()));
    }

    /// <summary>Thích / bỏ thích bình luận. Trả về số lượt thích mới.</summary>
    [HttpPost("comments/{commentId:guid}/like")]
    [RequireModulePermission("Communication", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<CommCommentDto>>> LikeComment(Guid commentId)
    {
        var v = await ViewerAsync();
        var c = await db.CommunicationComments.AsTracking()
            .FirstOrDefaultAsync(x => x.Id == commentId && x.Communication!.StoreId == RequiredStoreId);
        if (c == null) return Ok(AppResponse<CommCommentDto>.Error("Không tìm thấy bình luận"));
        var (p, err) = await VisiblePostAsync(c.CommunicationId, v);
        if (p == null) return Ok(AppResponse<CommCommentDto>.Error(err!));
        var mine = await db.CommunicationCommentLikes.AsTracking().FirstOrDefaultAsync(l => l.CommentId == commentId && l.UserId == v.UserId);
        if (mine != null) db.CommunicationCommentLikes.Remove(mine);
        else db.CommunicationCommentLikes.Add(new CommunicationCommentLike { Id = Guid.NewGuid(), StoreId = RequiredStoreId, CommentId = commentId, UserId = v.UserId });
        try { await db.SaveChangesAsync(); }
        catch (DbUpdateException) { db.ChangeTracker.Clear(); }
        var n = await db.CommunicationCommentLikes.CountAsync(l => l.CommentId == commentId);
        var tracked = await db.CommunicationComments.AsTracking().FirstAsync(x => x.Id == commentId);
        if (tracked.LikeCount != n) { tracked.LikeCount = n; await db.SaveChangesAsync(); }
        if (mine == null && c.UserId != v.UserId)
        {
            try
            {
                await notifications.CreateAndSendAsync(c.UserId, NotificationType.Info, "Truyền thông",
                    $"{v.DisplayName} thích bình luận của bạn", relatedEntityId: c.CommunicationId, relatedEntityType: "Communication",
                    fromUserId: v.UserId, categoryCode: "communication", storeId: RequiredStoreId);
            }
            catch { /* bỏ qua */ }
        }
        await BroadcastAsync("CommCommentChanged", new { postId = c.CommunicationId, commentId, action = "liked", by = v.UserId });
        return Ok(AppResponse<CommCommentDto>.Success((await CommentDtosAsync(new() { tracked }, v)).First()));
    }

    /// <summary>Ai đã bày tỏ cảm xúc với bài (lọc theo loại nếu có).</summary>
    [HttpGet("posts/{id:guid}/reactions")]
    [RequireModulePermission("Communication", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<CommReactorDto>>>> Reactors(Guid id, [FromQuery] int? type = null)
    {
        var v = await ViewerAsync();
        var (p, err) = await VisiblePostAsync(id, v);
        if (p == null) return Ok(AppResponse<List<CommReactorDto>>.Error(err!));
        var q = db.CommunicationReactions.AsNoTracking().Where(r => r.CommunicationId == id);
        if (type.HasValue) q = q.Where(r => (int)r.ReactionType == type.Value);
        var rows = await q.OrderByDescending(r => r.UpdatedAt ?? r.CreatedAt).Take(500)
            .Select(r => new { r.UserId, r.ReactionType }).ToListAsync();
        var uids = rows.Select(r => r.UserId).Distinct().ToList();
        var emps = await db.Employees.AsNoTracking()
            .Where(e => e.StoreId == RequiredStoreId && e.ApplicationUserId != null && uids.Contains(e.ApplicationUserId.Value))
            .Select(e => new { UserId = e.ApplicationUserId!.Value, e.LastName, e.FirstName, e.PhotoUrl }).ToListAsync();
        var users = await db.Users.AsNoTracking().Where(u => uids.Contains(u.Id))
            .Select(u => new { u.Id, u.LastName, u.FirstName, u.UserName }).ToListAsync();
        return Ok(AppResponse<List<CommReactorDto>>.Success(rows.Select(r =>
        {
            var e = emps.FirstOrDefault(x => x.UserId == r.UserId);
            var u = users.FirstOrDefault(x => x.Id == r.UserId);
            var name = e != null ? $"{e.LastName} {e.FirstName}".Trim() : $"{u?.LastName} {u?.FirstName}".Trim();
            if (string.IsNullOrWhiteSpace(name)) name = u?.UserName ?? "—";
            return new CommReactorDto { UserId = r.UserId, Name = name, Avatar = e?.PhotoUrl, Type = (int)r.ReactionType };
        }).ToList()));
    }

    [HttpDelete("comments/{commentId:guid}")]
    [RequireModulePermission("Communication", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<bool>>> DeleteComment(Guid commentId)
    {
        var v = await ViewerAsync();
        var c = await db.CommunicationComments.AsTracking()
            .Include(x => x.Communication)
            .FirstOrDefaultAsync(x => x.Id == commentId && x.Communication!.StoreId == RequiredStoreId);
        if (c == null) return Ok(AppResponse<bool>.Error("Không tìm thấy bình luận"));
        if (!v.IsManager && c.UserId != v.UserId) return Ok(AppResponse<bool>.Error("Bạn không xóa được bình luận này"));
        var replies = await db.CommunicationComments.AsTracking().Where(x => x.ParentCommentId == commentId).ToListAsync();
        var gone = replies.Select(x => x.Id).Append(commentId).ToList();
        db.CommunicationCommentLikes.RemoveRange(await db.CommunicationCommentLikes.AsTracking()
            .Where(l => gone.Contains(l.CommentId)).ToListAsync());
        db.CommunicationComments.RemoveRange(replies);
        db.CommunicationComments.Remove(c);
        await db.SaveChangesAsync();
        await CommentChangedAsync(c.CommunicationId, commentId, "deleted");
        return Ok(AppResponse<bool>.Success(true));
    }

    // ─── Ai đã đọc / nhắc đọc ─────────────────────────────────────

    [HttpGet("posts/{id:guid}/readers")]
    [RequireModulePermission("Communication", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<CommReadersDto>>> Readers(Guid id)
    {
        var v = await ViewerAsync();
        var p = await db.InternalCommunications.AsNoTracking().FirstOrDefaultAsync(x => x.Id == id && x.StoreId == RequiredStoreId);
        if (p == null) return Ok(AppResponse<CommReadersDto>.Error("Không tìm thấy bài viết"));
        if (!v.IsManager && p.AuthorId != v.UserId) return Ok(AppResponse<CommReadersDto>.Error("Chỉ quản lý hoặc người đăng xem được"));
        var map = await ChannelMapAsync();
        var ch = p.ChannelId.HasValue ? map.GetValueOrDefault(p.ChannelId.Value) : null;
        var people = await CommV2Helper.AudienceEmployeesAsync(db, RequiredStoreId, CommV2Helper.Audience(p.Audience), ch);
        var reads = await db.CommunicationReads.AsNoTracking().Where(r => r.CommunicationId == id).ToListAsync();
        var list = people.Select(e =>
        {
            var r = reads.FirstOrDefault(x => x.EmployeeId == e.EmployeeId || (e.UserId.HasValue && x.UserId == e.UserId));
            return new CommReaderDto
            {
                EmployeeId = e.EmployeeId,
                Name = e.Name,
                ReadAt = r?.FirstViewedAt,
                AckAt = r?.AcknowledgedAt,
                AckCurrent = r?.AcknowledgedAt != null && r.AckVersion >= p.Version,
            };
        }).OrderBy(x => x.AckCurrent).ThenBy(x => x.ReadAt != null).ThenBy(x => x.Name).ToList();
        return Ok(AppResponse<CommReadersDto>.Success(new CommReadersDto
        {
            AudienceCount = list.Count,
            ReadCount = list.Count(x => x.ReadAt != null),
            AckCount = list.Count(x => x.AckCurrent),
            People = list,
        }));
    }

    /// <summary>Nhắc người chưa đọc (hoặc chưa xác nhận nếu bài bắt buộc).</summary>
    [HttpPost("posts/{id:guid}/remind")]
    [RequireModulePermission("Communication", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<int>>> Remind(Guid id)
    {
        var readers = await Readers(id);
        if (readers.Result is not OkObjectResult { Value: AppResponse<CommReadersDto> r } || r.Data == null)
            return Ok(AppResponse<int>.Error("Không nhắc được"));
        var p = await db.InternalCommunications.AsNoTracking().FirstAsync(x => x.Id == id);
        var pending = r.Data.People.Where(x => p.RequireAck ? !x.AckCurrent : x.ReadAt == null).Select(x => x.EmployeeId).ToList();
        var userIds = await db.Employees.AsNoTracking()
            .Where(e => pending.Contains(e.Id) && e.ApplicationUserId != null).Select(e => e.ApplicationUserId!.Value).ToListAsync();
        if (userIds.Count > 0)
        {
            await notifications.CreateAndSendToUsersAsync(userIds, NotificationType.Reminder,
                p.RequireAck ? "Nhắc xác nhận đã đọc" : "Bài viết bạn chưa đọc",
                p.RequireAck ? $"Vui lòng đọc và xác nhận «{p.Title}»" : p.Title,
                relatedEntityId: id, relatedEntityType: "Communication", fromUserId: CurrentUserId,
                categoryCode: "communication", storeId: RequiredStoreId);
        }
        return Ok(AppResponse<int>.Success(userIds.Count));
    }

    private async Task NotifyAudienceAsync(InternalCommunication p, CommChannel? ch, Guid fromUserId, bool isUpdate)
    {
        try
        {
            var people = await CommV2Helper.AudienceEmployeesAsync(db, RequiredStoreId, CommV2Helper.Audience(p.Audience), ch);
            var ids = people.Where(x => x.UserId.HasValue && x.UserId != fromUserId).Select(x => x.UserId!.Value).Distinct().ToList();
            if (ids.Count == 0) return;
            var title = isUpdate
                ? (p.RequireAck ? "Văn bản cập nhật — cần xác nhận lại" : "Bài viết được cập nhật")
                : p.RequireAck ? "Văn bản mới — bắt buộc đọc" : $"{ch?.Name ?? "Truyền thông"}: bài mới";
            await notifications.CreateAndSendToUsersAsync(ids,
                p.Priority >= CommunicationPriority.High || p.RequireAck ? NotificationType.Warning : NotificationType.Info,
                title, p.Title, relatedEntityId: p.Id, relatedEntityType: "Communication", fromUserId: fromUserId,
                categoryCode: "communication", storeId: RequiredStoreId);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Notify communication audience failed {Id}", p.Id);
        }
    }

    private async Task NotifyManagersAsync(InternalCommunication p, string message)
    {
        try
        {
            var candidates = await db.Users.AsNoTracking()
                .Where(u => u.StoreId == RequiredStoreId && u.Role != null &&
                            u.Role != "Employee" && u.Role != "User" && u.Role != "Waiter" && u.Role != "Cashier")
                .Select(u => new { u.Id, u.Role }).Take(300).ToListAsync();
            var managers = new List<Guid>();
            foreach (var u in candidates)
            {
                if (u.Id == p.AuthorId) continue;
                if (ModulePermissionDefaults.IsSuperRole(u.Role!)
                    || await permissions.HasPermissionAsync(u.Id, u.Role!, RequiredStoreId, "Communication", ModulePermissionAction.Approve)
                    || await permissions.HasPermissionAsync(u.Id, u.Role!, RequiredStoreId, "Communication", ModulePermissionAction.Edit))
                    managers.Add(u.Id);
            }
            if (managers.Count > 0)
                await notifications.CreateAndSendToUsersAsync(managers, NotificationType.Info, "Bài chờ duyệt", message,
                    relatedEntityId: p.Id, relatedEntityType: "Communication", fromUserId: p.AuthorId,
                    categoryCode: "communication", storeId: RequiredStoreId);
        }
        catch { /* bỏ qua */ }
    }

    // ─── Cột phải: việc cần làm, sự kiện, sinh nhật ──────────────

    [HttpGet("sidebar")]
    [RequireModulePermission("Communication", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<CommSidebarDto>>> Sidebar()
    {
        var v = await ViewerAsync();
        var map = await ChannelMapAsync();
        var now = DateTime.UtcNow;
        var recent = now.AddDays(-180);
        var posts = await db.InternalCommunications.AsNoTracking()
            .Where(p => p.StoreId == RequiredStoreId && p.Status == CommunicationStatus.Published &&
                        ((p.RequireAck && p.PublishedAt >= recent) || (p.Poll != null && p.PublishedAt >= recent) ||
                         p.EventAt >= now.AddHours(-6)))
            .Select(p => new { p.Id, p.Title, p.ChannelId, p.Audience, p.AuthorId, p.Status, p.ExpiresAt, p.RequireAck, p.Version, p.AckDeadline, p.Poll, p.EventAt, p.EventLocation })
            .ToListAsync();
        var visible = posts.Where(p => Visible(new InternalCommunication { AuthorId = p.AuthorId, Status = p.Status, ExpiresAt = p.ExpiresAt, Audience = p.Audience },
            p.ChannelId.HasValue ? map.GetValueOrDefault(p.ChannelId.Value) : null, v with { IsManager = false }, now)).ToList();
        var acks = await db.CommunicationReads.AsNoTracking().Where(r => r.UserId == v.UserId && r.AcknowledgedAt != null)
            .ToDictionaryAsync(r => r.CommunicationId, r => r.AckVersion);
        var myVotes = (await db.CommunicationPollVotes.AsNoTracking().Where(x => x.UserId == v.UserId)
            .Select(x => x.CommunicationId).Distinct().ToListAsync()).ToHashSet();
        var required = visible.Where(p => p.RequireAck && (!acks.TryGetValue(p.Id, out var av) || av < p.Version))
            .OrderBy(p => p.AckDeadline ?? DateTime.MaxValue).ToList();
        var dto = new CommSidebarDto
        {
            RequiredPending = required.Count,
            Required = required.Take(5).Select(p => new CommPostBriefDto { Id = p.Id, Title = p.Title, Deadline = p.AckDeadline }).ToList(),
            OpenPolls = visible.Count(p => p.Poll != null && !myVotes.Contains(p.Id) &&
                                           (CommV2Helper.Parse<CommPoll>(p.Poll)?.ClosesAt is not DateTime c || c > now)),
            Events = visible.Where(p => p.EventAt >= now.AddHours(-6)).OrderBy(p => p.EventAt).Take(5)
                .Select(p => new CommPostBriefDto { Id = p.Id, Title = p.Title, At = p.EventAt, Location = p.EventLocation }).ToList(),
        };
        if (v.IsManager)
            dto.PendingApproval = await db.InternalCommunications.CountAsync(p => p.StoreId == RequiredStoreId && p.Status == CommunicationStatus.PendingApproval);

        // Sinh nhật 7 ngày tới (giờ Việt Nam).
        var today = DateTime.UtcNow.AddHours(7).Date;
        var emps = await db.Employees.AsNoTracking()
            .Where(e => e.StoreId == RequiredStoreId && e.Deleted == null && e.DateOfBirth != null && e.WorkStatus != EmployeeWorkStatus.Resigned)
            .Select(e => new { e.Id, e.LastName, e.FirstName, e.DateOfBirth, e.PhotoUrl }).ToListAsync();
        foreach (var e in emps)
        {
            var dob = e.DateOfBirth!.Value;
            for (var i = 0; i < 7; i++)
            {
                var d = today.AddDays(i);
                if (dob.Month == d.Month && (dob.Day == d.Day || (dob.Month == 2 && dob.Day == 29 && d.Day == 28 && !DateTime.IsLeapYear(d.Year))))
                {
                    dto.Birthdays.Add(new CommBirthdayDto { EmployeeId = e.Id, Name = $"{e.LastName} {e.FirstName}".Trim(), Date = d, PhotoUrl = e.PhotoUrl });
                    break;
                }
            }
        }
        dto.Birthdays = dto.Birthdays.OrderBy(b => b.Date).Take(10).ToList();
        return Ok(AppResponse<CommSidebarDto>.Success(dto));
    }

    [HttpGet("insights")]
    [Authorize(Policy = Application.Constants.PolicyNames.AtLeastManager)]
    [RequireModulePermission("Communication", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<CommInsightsDto>>> Insights()
    {
        var map = await ChannelMapAsync();
        var since = DateTime.UtcNow.AddDays(-30);
        var posts = await db.InternalCommunications.AsNoTracking()
            .Where(p => p.StoreId == RequiredStoreId && p.Status == CommunicationStatus.Published && (p.PublishedAt >= since || p.RequireAck))
            .OrderByDescending(p => p.PublishedAt).Take(60).ToListAsync();
        var ids = posts.Select(p => p.Id).ToList();
        var reads = await db.CommunicationReads.AsNoTracking().Where(r => ids.Contains(r.CommunicationId))
            .Select(r => new { r.CommunicationId, r.AcknowledgedAt, r.AckVersion }).ToListAsync();
        var reacts = await db.CommunicationReactions.AsNoTracking().Where(r => ids.Contains(r.CommunicationId))
            .GroupBy(r => r.CommunicationId).Select(g => new { g.Key, N = g.Count() }).ToDictionaryAsync(x => x.Key, x => x.N);
        var comms = await db.CommunicationComments.AsNoTracking().Where(r => ids.Contains(r.CommunicationId))
            .GroupBy(r => r.CommunicationId).Select(g => new { g.Key, N = g.Count() }).ToDictionaryAsync(x => x.Key, x => x.N);
        var cache = new Dictionary<string, int>();
        var dto = new CommInsightsDto();
        foreach (var p in posts)
        {
            var ch = p.ChannelId.HasValue ? map.GetValueOrDefault(p.ChannelId.Value) : null;
            var key = $"{p.Audience}|{ch?.BranchId}|{ch?.DepartmentId}";
            if (!cache.TryGetValue(key, out var aud))
                cache[key] = aud = (await CommV2Helper.AudienceEmployeesAsync(db, RequiredStoreId, CommV2Helper.Audience(p.Audience), ch)).Count;
            var pr = reads.Where(r => r.CommunicationId == p.Id).ToList();
            dto.Posts.Add(new CommPostStatDto
            {
                Id = p.Id,
                Title = p.Title,
                ChannelName = ch?.Name,
                PublishedAt = p.PublishedAt,
                Audience = aud,
                Read = Math.Min(aud, pr.Count),
                Acked = Math.Min(aud, pr.Count(r => r.AcknowledgedAt != null && r.AckVersion >= p.Version)),
                RequireAck = p.RequireAck,
                Reactions = reacts.GetValueOrDefault(p.Id),
                Comments = comms.GetValueOrDefault(p.Id),
            });
        }
        var recent = dto.Posts.Where(x => x.PublishedAt >= since).ToList();
        dto.Posts30 = recent.Count;
        dto.AvgReadRate = recent.Count == 0 ? 0 : Math.Round(recent.Average(x => x.Audience == 0 ? 0 : x.Read * 100.0 / x.Audience), 1);
        dto.RequiredPosts = dto.Posts.Count(x => x.RequireAck);
        dto.OutstandingAcks = dto.Posts.Where(x => x.RequireAck).Sum(x => Math.Max(0, x.Audience - x.Acked));
        return Ok(AppResponse<CommInsightsDto>.Success(dto));
    }

    // ─── Tải tệp ──────────────────────────────────────────────────

    private async Task<string> StoreFolderAsync()
    {
        var code = await db.Stores.AsNoTracking().Where(s => s.Id == RequiredStoreId).Select(s => s.Code).FirstOrDefaultAsync();
        return string.IsNullOrEmpty(code) ? "uploads/communications" : $"stores/{code}/uploads/communications";
    }

    /// <summary>Lưu một tệp (ảnh được nén). Trả về đính kèm và nội dung gốc (để AI đọc).</summary>
    private async Task<(CommAttachment? att, byte[]? data, string? error)> SaveFileAsync(IFormFile file)
    {
        if (file.Length == 0) return (null, null, $"{file.FileName}: tệp rỗng");
        if (file.Length > MaxFileBytes) return (null, null, $"{file.FileName}: vượt quá 20 MB");
        var name = Path.GetFileName(file.FileName);
        var ext = Path.GetExtension(name).ToLowerInvariant();
        if (!CommDocumentReader.MimeByExt.ContainsKey(ext)) return (null, null, $"{name}: định dạng không hỗ trợ");
        using var ms = new MemoryStream();
        await file.CopyToAsync(ms);
        var data = ms.ToArray();
        if (!CommDocumentReader.MagicMatches(data, name)) return (null, null, $"{name}: nội dung không khớp định dạng");
        var folder = await StoreFolderAsync();
        var kind = CommDocumentReader.KindOf(name);
        string stored;
        long size = data.Length;
        if (kind == "image" && ext != ".gif")
        {
            var (optimized, uploadName, _) = await ImageOptimizeHelper.OptimizeAsync(new MemoryStream(data), name,
                ImageOptimizeHelper.PhotoMaxEdge, ImageOptimizeHelper.PhotoJpegQuality);
            await using (optimized)
            {
                size = optimized.Length;
                stored = await storage.UploadAsync(optimized, uploadName, folder);
            }
        }
        else
        {
            stored = await storage.UploadAsync(new MemoryStream(data), name, folder);
        }
        return (new CommAttachment
        {
            Url = storage.GetFileUrl(stored),
            Name = name,
            Mime = CommDocumentReader.MimeByExt[ext],
            Size = size,
            Kind = kind,
        }, data, null);
    }

    [HttpPost("upload")]
    [RequestSizeLimit(MaxFileBytes * MaxFilesPerPost + 1024 * 1024)]
    [RequireModulePermission("Communication", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<CommAiDocumentResultDto>>> Upload([FromForm] List<IFormFile> files)
    {
        var result = new CommAiDocumentResultDto();
        foreach (var f in files.Take(MaxFilesPerPost))
        {
            var (att, _, err) = await SaveFileAsync(f);
            if (att != null) result.Attachments.Add(att);
            if (err != null) result.Warnings.Add(err);
        }
        if (files.Count > MaxFilesPerPost) result.Warnings.Add($"Chỉ nhận {MaxFilesPerPost} tệp đầu tiên");
        return Ok(AppResponse<CommAiDocumentResultDto>.Success(result));
    }

    // ─── AI ───────────────────────────────────────────────────────

    private const string AiSystem =
        "Bạn là biên tập viên truyền thông nội bộ của một doanh nghiệp Việt Nam. Viết tiếng Việt có dấu, rõ ràng, " +
        "câu ngắn, dễ đọc trên điện thoại. KHÔNG bịa số liệu, ngày tháng, tên người, mức phạt hay quy định không có trong nguồn. " +
        "Trả về DUY NHẤT một JSON object theo schema: " +
        "{\"title\":string,\"summary\":string (1-2 câu),\"blocks\":[{\"type\":\"h2|h3|p|bullet|ordered|quote\",\"text\":string}]," +
        "\"keyPoints\":[string],\"faq\":[{\"q\":string,\"a\":string}],\"tags\":[string]," +
        "\"suggestedChannel\":\"feed|announcement|policy|hr|event|training|culture|docs\",\"suggestRequireAck\":boolean}. " +
        "Trong text có thể dùng **chữ đậm**. Mỗi mục danh sách là một block bullet/ordered riêng.";

    private static string ToneText(string? tone) => tone?.ToLowerInvariant() switch
    {
        "friendly" => "thân thiện, gần gũi",
        "formal" => "trang trọng, chuẩn mực văn bản hành chính",
        "inspirational" => "truyền cảm hứng",
        "short" => "ngắn gọn, đi thẳng vào ý chính",
        _ => "chuyên nghiệp, rõ ràng",
    };

    private async Task<CommAiDraftDto?> RunAiAsync(string user, IReadOnlyList<AiFilePart>? files, CancellationToken ct)
    {
        var raw = await gemini.GenerateJsonAsync(AiSystem, user, files, 12000, ct);
        var json = raw.Trim();
        var start = json.IndexOf('{');
        var end = json.LastIndexOf('}');
        if (start < 0 || end <= start) return null;
        json = json[start..(end + 1)];
        try
        {
            var d = JsonSerializer.Deserialize<CommAiDraftDto>(json, new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
            if (d == null) return null;
            d.Blocks = d.Blocks.Where(b => !string.IsNullOrWhiteSpace(b.Text)).ToList();
            return d;
        }
        catch (JsonException)
        {
            return null;
        }
    }

    [HttpPost("ai/write")]
    [RequireModulePermission("Communication", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<CommAiDraftDto>>> AiWrite([FromBody] CommAiWriteDto d, CancellationToken ct)
    {
        var task = d.Action switch
        {
            "improve" => "Viết lại bài dưới đây cho hay hơn, mạch lạc hơn, giữ nguyên ý và số liệu.",
            "shorten" => "Rút gọn bài dưới đây còn khoảng một nửa, giữ ý chính.",
            "expand" => "Viết bài dưới đây chi tiết hơn, thêm giải thích và ví dụ hợp lý (không bịa số liệu).",
            "fix" => "Sửa lỗi chính tả, ngữ pháp, dấu câu của bài dưới đây; giữ nguyên nội dung và cấu trúc.",
            "summarize" => "Tóm tắt bài dưới đây thành các ý chính.",
            "announce" => "Chuyển nội dung dưới đây thành một thông báo chính thức: có tiêu đề, đối tượng áp dụng, hiệu lực, nội dung, liên hệ.",
            _ => "Viết một bài truyền thông nội bộ theo yêu cầu.",
        };
        var sb = new System.Text.StringBuilder();
        sb.AppendLine(task);
        sb.AppendLine($"Giọng văn: {ToneText(d.Tone)}.");
        if (!string.IsNullOrWhiteSpace(d.ChannelKey)) sb.AppendLine($"Kênh đăng: {d.ChannelKey}.");
        if (!string.IsNullOrWhiteSpace(d.Prompt)) sb.AppendLine($"Yêu cầu: {d.Prompt.Trim()}");
        if (!string.IsNullOrWhiteSpace(d.Title)) sb.AppendLine($"Tiêu đề hiện tại: {d.Title.Trim()}");
        if (!string.IsNullOrWhiteSpace(d.CurrentText))
        {
            var t = d.CurrentText.Length > 30000 ? d.CurrentText[..30000] : d.CurrentText;
            sb.AppendLine("--- NỘI DUNG HIỆN TẠI ---").AppendLine(t);
        }
        if (string.IsNullOrWhiteSpace(d.Prompt) && string.IsNullOrWhiteSpace(d.CurrentText))
            return Ok(AppResponse<CommAiDraftDto>.Error("Nhập yêu cầu hoặc nội dung để AI viết"));
        try
        {
            var draft = await RunAiAsync(sb.ToString(), null, ct);
            return draft == null
                ? Ok(AppResponse<CommAiDraftDto>.Error("AI trả kết quả không đọc được — thử lại"))
                : Ok(AppResponse<CommAiDraftDto>.Success(draft));
        }
        catch (Exception ex) when (ex is InvalidOperationException or AiApiException or HttpRequestException)
        {
            return Ok(AppResponse<CommAiDraftDto>.Error(ex.Message));
        }
    }

    /// <summary>
    /// Tải tài liệu (Word, PDF, Excel, PowerPoint, ảnh) → lưu làm đính kèm và AI đọc, viết lại thành bài.
    /// </summary>
    [HttpPost("ai/from-documents")]
    [RequestSizeLimit(MaxFileBytes * MaxFilesPerPost + 1024 * 1024)]
    [RequireModulePermission("Communication", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<CommAiDocumentResultDto>>> AiFromDocuments(
        [FromForm] List<IFormFile> files, [FromForm] string? instruction, [FromForm] string? tone,
        [FromForm] string? channelKey, CancellationToken ct)
    {
        var result = new CommAiDocumentResultDto();
        if (files.Count == 0) return Ok(AppResponse<CommAiDocumentResultDto>.Error("Chọn ít nhất một tài liệu"));
        var texts = new System.Text.StringBuilder();
        var parts = new List<AiFilePart>();
        long inlineBytes = 0;
        foreach (var f in files.Take(MaxFilesPerPost))
        {
            var (att, data, err) = await SaveFileAsync(f);
            if (err != null) result.Warnings.Add(err);
            if (att == null || data == null) continue;
            result.Attachments.Add(att);
            var doc = CommDocumentReader.Read(data, att.Name);
            if (doc.Warning != null) result.Warnings.Add(doc.Warning);
            if (doc.Text != null && texts.Length < CommDocumentReader.MaxTextChars)
                texts.AppendLine($"=== TÀI LIỆU: {att.Name} ===").AppendLine(doc.Text).AppendLine();
            if (doc.FilePart != null)
            {
                if (inlineBytes + doc.FilePart.Data.Length > CommDocumentReader.MaxInlineBytes)
                    result.Warnings.Add($"{att.Name}: vượt tổng dung lượng AI đọc một lần (18 MB) — vẫn được đính kèm.");
                else
                {
                    parts.Add(doc.FilePart);
                    inlineBytes += doc.FilePart.Data.Length;
                }
            }
        }
        if (texts.Length == 0 && parts.Count == 0)
        {
            result.Warnings.Add("AI không đọc được nội dung tài liệu nào — tệp vẫn được đính kèm để bạn tự viết bài.");
            return Ok(AppResponse<CommAiDocumentResultDto>.Success(result));
        }
        var user = new System.Text.StringBuilder()
            .AppendLine("Đọc (các) tài liệu nội bộ dưới đây và dựng lại thành MỘT bài truyền thông nội bộ để đăng lên bảng tin công ty.")
            .AppendLine("Giữ đúng quy định, con số, ngày hiệu lực trong tài liệu. Nếu là nội quy/chính sách: nêu rõ đối tượng áp dụng, hiệu lực, " +
                        "các điểm chính, điều cần làm; đặt suggestRequireAck=true. Thêm 3–5 câu hỏi thường gặp nếu hữu ích.")
            .AppendLine($"Giọng văn: {ToneText(tone)}.");
        if (!string.IsNullOrWhiteSpace(channelKey)) user.AppendLine($"Kênh đăng dự kiến: {channelKey}.");
        if (!string.IsNullOrWhiteSpace(instruction)) user.AppendLine($"Yêu cầu thêm của người đăng: {instruction.Trim()}");
        if (parts.Count > 0) user.AppendLine("PDF/ảnh đính kèm cũng là nguồn nội dung (với PDF dài, tập trung khoảng 30 trang đầu).");
        if (texts.Length > 0) user.AppendLine().Append(texts);
        try
        {
            result.Draft = await RunAiAsync(user.ToString(), parts, ct);
            if (result.Draft == null) result.Warnings.Add("AI trả kết quả không đọc được — thử lại hoặc tự viết bài.");
        }
        catch (Exception ex) when (ex is InvalidOperationException or AiApiException or HttpRequestException)
        {
            result.Warnings.Add(ex.Message);
        }
        return Ok(AppResponse<CommAiDocumentResultDto>.Success(result));
    }
}

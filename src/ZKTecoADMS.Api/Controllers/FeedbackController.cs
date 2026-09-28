using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using System.Text.Json;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Application.Services;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// Kiến nghị / khiếu nại / góp ý của nhân viên: gửi (có thể ẩn danh) tới hòm thư chung hoặc 1 người xử lý,
/// trao đổi 2 chiều, giao người xử lý, mức độ + hạn xử lý, ghi chú nội bộ, mở lại, đánh giá hài lòng, báo cáo.
/// </summary>
[ApiController]
[Route("api/[controller]")]
[Authorize]
public class FeedbackController(
    ZKTecoDbContext dbContext,
    ISystemNotificationService notificationService,
    IFileStorageService fileStorageService) : AuthenticatedControllerBase
{
    const int KindMessage = 0, KindInternal = 1, KindEvent = 2;
    static readonly string[] HandlerRoles = ["Admin", "Director", "Manager", "DepartmentHead", "Accountant", "SuperAdmin"];

    #region DTOs

    public record FeedbackCreateDto(
        string Title, string Content, string Category,
        bool IsAnonymous, Guid? RecipientEmployeeId,
        string? Topic = null, int? Priority = null, List<string>? ImageUrls = null);

    public record FeedbackRespondDto(string Response, string Status);

    public record FeedbackStatusDto(string Status, string? Note = null);

    public record FeedbackManageDto(
        int? Priority = null, Guid? AssigneeEmployeeId = null, bool ClearAssignee = false,
        string? Topic = null, DateTime? DueAt = null);

    public record FeedbackReopenDto(string? Reason);

    public record FeedbackRateDto(int Rating, string? Comment);

    public record FeedbackReplyCreateDto(string Content, bool Internal = false);

    public record FeedbackReplyDto(
        Guid Id, Guid FeedbackId, string Content, List<string>? ImageUrls,
        bool IsFromSender, string? SenderName, Guid? SenderEmployeeId,
        DateTime CreatedAt, bool IsMine = false, int Kind = 0);

    #endregion

    // ══════════════════ NGƯỜI XEM / QUYỀN ══════════════════

    /// <summary>Quản lý / trưởng bộ phận / kế toán: người xử lý kiến nghị.</summary>
    bool IsHandler => IsManager || IsAccountant;

    private async Task<Guid?> ResolveEmployeeIdAsync()
    {
        var empId = EmployeeId;
        if (empId.HasValue) return empId;
        var userId = CurrentUserId;
        var employee = await dbContext.Employees
            .Where(e => e.ApplicationUserId == userId && e.Deleted == null)
            .Select(e => e.Id)
            .FirstOrDefaultAsync();
        return employee == default ? null : employee;
    }

    sealed record Viewer(Guid? EmployeeId, string UserId, bool FullAccess, bool Handler);

    async Task<Viewer> ViewerAsync() =>
        new(await ResolveEmployeeIdAsync(), CurrentUserId.ToString(), IsAdmin, IsHandler);

    static bool IsSender(Feedback f, Viewer v) =>
        (v.EmployeeId.HasValue && f.SenderEmployeeId == v.EmployeeId) || f.CreatedBy == v.UserId;

    static bool CanView(Feedback f, Viewer v) => FeedbackRules.CanView(
        v.FullAccess, v.Handler, IsSender(f, v),
        v.EmployeeId.HasValue && f.RecipientEmployeeId == v.EmployeeId,
        v.EmployeeId.HasValue && f.AssigneeEmployeeId == v.EmployeeId,
        f.RecipientEmployeeId == null);

    static bool CanManage(Feedback f, Viewer v) => FeedbackRules.CanManage(
        v.FullAccess, v.Handler, IsSender(f, v),
        v.EmployeeId.HasValue && f.RecipientEmployeeId == v.EmployeeId,
        v.EmployeeId.HasValue && f.AssigneeEmployeeId == v.EmployeeId,
        f.RecipientEmployeeId == null);

    /// <summary>Phiếu người xem được thấy (cùng quy tắc với <see cref="CanView"/>, dịch được sang SQL).</summary>
    IQueryable<Feedback> Scoped(Guid storeId, Viewer v)
    {
        var q = dbContext.Feedbacks.Where(f => f.StoreId == storeId && f.Deleted == null);
        if (v.FullAccess) return q;
        var emp = v.EmployeeId ?? Guid.Empty; // tránh so sánh null == null lọt hòm thư chung
        var uid = v.UserId;
        return v.Handler
            ? q.Where(f => f.RecipientEmployeeId == null || f.RecipientEmployeeId == emp || f.AssigneeEmployeeId == emp
                           || f.SenderEmployeeId == emp || f.CreatedBy == uid)
            : q.Where(f => f.SenderEmployeeId == emp || f.CreatedBy == uid
                           || f.RecipientEmployeeId == emp || f.AssigneeEmployeeId == emp);
    }

    // ══════════════════ TÊN / THÔNG BÁO ══════════════════

    sealed record EmpInfo(string Name, string? Code, string? Department, Guid? UserId);

    async Task<Dictionary<Guid, EmpInfo>> EmployeesAsync(IEnumerable<Guid?> ids)
    {
        var list = ids.Where(i => i.HasValue).Select(i => i!.Value).Distinct().ToList();
        if (list.Count == 0) return [];
        return await dbContext.Employees.IgnoreQueryFilters()
            .Where(e => list.Contains(e.Id))
            .ToDictionaryAsync(e => e.Id,
                e => new EmpInfo((e.LastName + " " + e.FirstName).Trim(), e.EmployeeCode, e.Department, e.ApplicationUserId));
    }

    async Task<Dictionary<string, string>> UserNamesAsync(IEnumerable<string?> ids)
    {
        var list = ids.Where(s => !string.IsNullOrEmpty(s)).Select(s => s!).Distinct().ToList();
        var guids = list.Select(s => Guid.TryParse(s, out var g) ? g : Guid.Empty).Where(g => g != Guid.Empty).ToList();
        if (guids.Count == 0) return [];
        return await dbContext.Users
            .Where(u => guids.Contains(u.Id))
            .ToDictionaryAsync(u => u.Id.ToString(), u => ((u.LastName ?? "") + " " + (u.FirstName ?? "")).Trim());
    }

    async Task<Guid?> UserIdOfEmployeeAsync(Guid? employeeId, string? createdBy = null)
    {
        if (employeeId.HasValue)
        {
            var uid = await dbContext.Employees
                .Where(e => e.Id == employeeId.Value && e.ApplicationUserId != null)
                .Select(e => e.ApplicationUserId!.Value)
                .FirstOrDefaultAsync();
            if (uid != Guid.Empty) return uid;
        }
        if (Guid.TryParse(createdBy, out var cu) && await dbContext.Users.AnyAsync(u => u.Id == cu)) return cu;
        return null;
    }

    async Task<string> MyNameAsync(Guid? employeeId)
    {
        if (employeeId.HasValue)
        {
            var n = await dbContext.Employees.Where(e => e.Id == employeeId.Value)
                .Select(e => (e.LastName + " " + e.FirstName).Trim()).FirstOrDefaultAsync();
            if (!string.IsNullOrWhiteSpace(n)) return n;
        }
        var names = await UserNamesAsync([CurrentUserId.ToString()]);
        return names.GetValueOrDefault(CurrentUserId.ToString()) is { Length: > 0 } un ? un : "Nhân viên";
    }

    /// <summary>Người xử lý cần biết: người nhận, người được giao, người đã trả lời; hòm thư chung → quản lý cửa hàng.</summary>
    async Task<List<Guid>> HandlerUserIdsAsync(Feedback f)
    {
        var targets = new HashSet<Guid>();
        foreach (var emp in new[] { f.RecipientEmployeeId, f.AssigneeEmployeeId })
            if (await UserIdOfEmployeeAsync(emp) is { } uid) targets.Add(uid);

        var repliers = await dbContext.FeedbackReplies
            .Where(r => r.FeedbackId == f.Id && !r.IsFromSender && r.CreatedBy != null && r.Kind != KindEvent)
            .Select(r => r.CreatedBy!).Distinct().ToListAsync();
        foreach (var s in repliers)
            if (Guid.TryParse(s, out var uid)) targets.Add(uid);

        if (!f.RecipientEmployeeId.HasValue && !f.AssigneeEmployeeId.HasValue)
        {
            var managers = await dbContext.Users
                .Where(u => u.IsActive && u.StoreId == f.StoreId &&
                            (u.Role == "Admin" || u.Role == "SuperAdmin" || u.Role == "Manager" ||
                             u.Role == "StoreOwner" || u.Role == "Director"))
                .Select(u => u.Id).ToListAsync();
            foreach (var id in managers) targets.Add(id);
        }
        // Không báo lại cho người gửi qua kênh «người xử lý» (tránh lộ ghi chú nội bộ / ẩn danh)
        if (await UserIdOfEmployeeAsync(f.SenderEmployeeId, f.CreatedBy) is { } senderUid) targets.Remove(senderUid);
        targets.Remove(CurrentUserId);
        return targets.ToList();
    }

    async Task NotifyAsync(IEnumerable<Guid> userIds, Feedback f, string title, string message)
    {
        var list = userIds.Where(u => u != CurrentUserId).Distinct().ToList();
        if (list.Count == 0) return;
        try
        {
            await notificationService.CreateAndSendToUsersAsync(
                list, NotificationType.Info, title, message,
                relatedEntityType: "Feedback", relatedEntityId: f.Id,
                fromUserId: CurrentUserId, categoryCode: "feedback", storeId: f.StoreId);
        }
        catch { /* thông báo lỗi không ảnh hưởng nghiệp vụ */ }
    }

    async Task NotifySenderAsync(Feedback f, string title, string message)
    {
        if (await UserIdOfEmployeeAsync(f.SenderEmployeeId, f.CreatedBy) is { } uid)
            await NotifyAsync([uid], f, title, message);
    }

    void AddEvent(Feedback f, Guid? employeeId, string text) =>
        dbContext.FeedbackReplies.Add(new FeedbackReply
        {
            Id = Guid.NewGuid(),
            FeedbackId = f.Id,
            SenderEmployeeId = employeeId,
            Content = text,
            IsFromSender = false,
            Kind = KindEvent,
            StoreId = f.StoreId,
            CreatedBy = CurrentUserId.ToString(),
        });

    static string Label(Feedback f) => string.IsNullOrEmpty(f.Code) ? $"\"{f.Title}\"" : $"{f.Code} \"{f.Title}\"";

    // ══════════════════ DTO PHIẾU ══════════════════

    async Task<List<object>> ToDtosAsync(List<Feedback> items, Viewer v, Dictionary<Guid, int>? replyCounts = null)
    {
        var now = DateTime.Now;
        var emps = await EmployeesAsync(items.SelectMany(f =>
            new[] { f.SenderEmployeeId, f.RecipientEmployeeId, f.AssigneeEmployeeId, f.RespondedByEmployeeId }));
        var users = await UserNamesAsync(items.SelectMany(f => new[] { f.CreatedBy, f.UpdatedBy }));
        if (replyCounts == null)
        {
            var ids = items.Select(f => f.Id).ToList();
            replyCounts = await dbContext.FeedbackReplies
                .Where(r => ids.Contains(r.FeedbackId) && r.Kind == KindMessage)
                .GroupBy(r => r.FeedbackId)
                .Select(g => new { g.Key, Count = g.Count() })
                .ToDictionaryAsync(x => x.Key, x => x.Count);
        }

        return items.Select(f =>
        {
            var mine = IsSender(f, v);
            var hide = f.IsAnonymous && !mine; // ẩn danh: không ai (kể cả admin) thấy người gửi
            var sender = f.SenderEmployeeId.HasValue ? emps.GetValueOrDefault(f.SenderEmployeeId.Value) : null;
            var senderName = hide ? null : sender?.Name ?? users.GetValueOrDefault(f.CreatedBy ?? "");
            var responder = f.RespondedByEmployeeId.HasValue ? emps.GetValueOrDefault(f.RespondedByEmployeeId.Value)?.Name : null;
            return (object)new
            {
                id = f.Id,
                code = f.Code,
                title = f.Title,
                content = f.Content,
                category = f.Category,
                categoryName = FeedbackRules.CategoryName(f.Category),
                topic = f.Topic,
                status = f.Status,
                statusName = FeedbackRules.StatusName(f.Status),
                priority = f.Priority,
                priorityName = FeedbackRules.PriorityName(f.Priority),
                isAnonymous = f.IsAnonymous,
                senderName,
                senderCode = hide ? null : sender?.Code,
                senderDepartment = hide ? null : sender?.Department,
                senderEmployeeId = hide ? null : f.SenderEmployeeId,
                recipientEmployeeId = f.RecipientEmployeeId,
                recipientName = f.RecipientEmployeeId.HasValue ? emps.GetValueOrDefault(f.RecipientEmployeeId.Value)?.Name : null,
                assigneeEmployeeId = f.AssigneeEmployeeId,
                assigneeName = f.AssigneeEmployeeId.HasValue ? emps.GetValueOrDefault(f.AssigneeEmployeeId.Value)?.Name : null,
                response = f.Response,
                respondedByName = responder ?? (f.Response != null ? users.GetValueOrDefault(f.UpdatedBy ?? "") : null),
                respondedAt = f.RespondedAt,
                createdAt = f.CreatedAt,
                updatedAt = f.UpdatedAt,
                dueAt = f.DueAt,
                overdue = FeedbackRules.IsOverdue(f.Status, f.DueAt, now),
                firstResponseAt = f.FirstResponseAt,
                resolvedAt = f.ResolvedAt,
                rating = f.Rating,
                ratingComment = f.RatingComment,
                reopenCount = f.ReopenCount,
                imageUrls = ParseImageUrls(f.ImageUrls),
                replyCount = replyCounts.GetValueOrDefault(f.Id),
                isMine = mine,
                canManage = CanManage(f, v),
            };
        }).ToList();
    }

    // ══════════════════ DANH SÁCH ══════════════════

    IQueryable<Feedback> ApplyFilters(IQueryable<Feedback> q, string? status, string? category, string? topic,
        int? priority, Guid? senderEmployeeId, Guid? recipientEmployeeId, bool? generalMailboxOnly,
        bool? overdue, string? search, DateTime? fromDate, DateTime? toDate)
    {
        var now = DateTime.Now;
        if (status == "Open") q = q.Where(f => f.Status == FeedbackRules.Pending || f.Status == FeedbackRules.InProgress);
        else if (!string.IsNullOrEmpty(status)) q = q.Where(f => f.Status == status);
        if (!string.IsNullOrEmpty(category)) q = q.Where(f => f.Category == category);
        if (!string.IsNullOrEmpty(topic)) q = q.Where(f => f.Topic == topic);
        if (priority.HasValue) q = q.Where(f => f.Priority == priority);
        // Lọc theo người gửi không bao giờ trả phiếu ẩn danh (tránh dò ra người gửi ẩn danh)
        if (senderEmployeeId.HasValue) q = q.Where(f => !f.IsAnonymous && f.SenderEmployeeId == senderEmployeeId);
        if (generalMailboxOnly == true) q = q.Where(f => f.RecipientEmployeeId == null);
        else if (recipientEmployeeId.HasValue) q = q.Where(f => f.RecipientEmployeeId == recipientEmployeeId);
        if (overdue == true)
            q = q.Where(f => (f.Status == FeedbackRules.Pending || f.Status == FeedbackRules.InProgress)
                             && f.DueAt != null && f.DueAt < now);
        if (!string.IsNullOrWhiteSpace(search))
        {
            var k = search.Trim().ToLower();
            q = q.Where(f => f.Title.ToLower().Contains(k) || f.Content.ToLower().Contains(k)
                             || (f.Code != null && f.Code.ToLower().Contains(k)));
        }
        if (fromDate.HasValue) q = q.Where(f => f.CreatedAt >= fromDate.Value.Date);
        if (toDate.HasValue) q = q.Where(f => f.CreatedAt < toDate.Value.Date.AddDays(1));
        return q;
    }

    /// <summary>Hòm thư xử lý: phiếu người xem được thấy, trừ phiếu chính mình gửi.</summary>
    [HttpGet]
    [RequireModulePermission("Feedback", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> GetAll(
        [FromQuery] string? status, [FromQuery] string? category, [FromQuery] string? topic,
        [FromQuery] int? priority,
        [FromQuery] Guid? senderEmployeeId, [FromQuery] Guid? recipientEmployeeId,
        [FromQuery] bool? generalMailboxOnly, [FromQuery] bool? assignedToMe, [FromQuery] bool? overdue,
        [FromQuery] string? search,
        [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate,
        [FromQuery] int page = 1, [FromQuery] int pageSize = 20)
    {
        var storeId = RequiredStoreId;
        var v = await ViewerAsync();
        var emp = v.EmployeeId ?? Guid.Empty;
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 1, 100);

        var baseQ = Scoped(storeId, v).Where(f => f.SenderEmployeeId != emp && f.CreatedBy != v.UserId);
        var now = DateTime.Now;
        var counts = new
        {
            open = await baseQ.CountAsync(f => f.Status == FeedbackRules.Pending || f.Status == FeedbackRules.InProgress),
            pending = await baseQ.CountAsync(f => f.Status == FeedbackRules.Pending),
            inProgress = await baseQ.CountAsync(f => f.Status == FeedbackRules.InProgress),
            overdue = await baseQ.CountAsync(f => (f.Status == FeedbackRules.Pending || f.Status == FeedbackRules.InProgress)
                                                  && f.DueAt != null && f.DueAt < now),
            assignedToMe = await baseQ.CountAsync(f => f.AssigneeEmployeeId == emp
                                                       && (f.Status == FeedbackRules.Pending || f.Status == FeedbackRules.InProgress)),
            resolved = await baseQ.CountAsync(f => f.Status == FeedbackRules.Resolved),
            all = await baseQ.CountAsync(),
        };

        var q = ApplyFilters(baseQ, status, category, topic, priority, senderEmployeeId, recipientEmployeeId,
            generalMailboxOnly, overdue, search, fromDate, toDate);
        if (assignedToMe == true) q = q.Where(f => f.AssigneeEmployeeId == emp);

        var total = await q.CountAsync();
        // Ưu tiên: đang mở trước, mức độ cao trước, hạn gần trước; rồi mới nhất
        var rows = await q
            .OrderBy(f => f.Status == FeedbackRules.Pending || f.Status == FeedbackRules.InProgress ? 0 : 1)
            .ThenByDescending(f => f.Status == FeedbackRules.Pending || f.Status == FeedbackRules.InProgress ? f.Priority : 0)
            .ThenBy(f => f.Status == FeedbackRules.Pending || f.Status == FeedbackRules.InProgress ? f.DueAt : null)
            .ThenByDescending(f => f.CreatedAt)
            .Skip((page - 1) * pageSize).Take(pageSize)
            .ToListAsync();

        var items = await ToDtosAsync(rows, v);
        return Ok(AppResponse<object>.Success(new { items, total, page, pageSize, counts }));
    }

    /// <summary>Phiếu tôi đã gửi.</summary>
    [HttpGet("my")]
    [RequireModulePermission("Feedback", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<object>>>> GetMyFeedbacks(
        [FromQuery] string? status, [FromQuery] string? category, [FromQuery] string? topic,
        [FromQuery] string? search,
        [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate)
    {
        var storeId = RequiredStoreId;
        var v = await ViewerAsync();
        var emp = v.EmployeeId ?? Guid.Empty;
        var q = dbContext.Feedbacks.Where(f => f.StoreId == storeId && f.Deleted == null
                                               && (f.SenderEmployeeId == emp || f.CreatedBy == v.UserId));
        q = ApplyFilters(q, status, category, topic, null, null, null, null, null, search, fromDate, toDate);
        var rows = await q.OrderByDescending(f => f.UpdatedAt ?? f.CreatedAt).Take(300).ToListAsync();
        return Ok(AppResponse<List<object>>.Success(await ToDtosAsync(rows, v)));
    }

    // ══════════════════ GỬI PHIẾU ══════════════════

    [HttpPost]
    [RequireModulePermission("Feedback", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<object>>> Create([FromBody] FeedbackCreateDto dto)
    {
        var storeId = RequiredStoreId;
        var v = await ViewerAsync();

        var title = dto.Title?.Trim() ?? "";
        var content = dto.Content?.Trim() ?? "";
        if (title.Length == 0 || content.Length == 0)
            return Ok(AppResponse<object>.Error("Vui lòng nhập tiêu đề và nội dung"));
        if (title.Length > 300) return Ok(AppResponse<object>.Error("Tiêu đề tối đa 300 ký tự"));
        if (content.Length > 5000) return Ok(AppResponse<object>.Error("Nội dung tối đa 5000 ký tự"));

        if (dto.RecipientEmployeeId.HasValue &&
            !await dbContext.Employees.AnyAsync(e => e.Id == dto.RecipientEmployeeId && e.StoreId == storeId && e.Deleted == null))
            return Ok(AppResponse<object>.Error("Người nhận không hợp lệ"));

        var category = FeedbackRules.Categories.Contains(dto.Category) ? dto.Category : "General";
        var priority = dto.Priority.HasValue
            ? FeedbackRules.NormalizePriority(dto.Priority.Value)
            : FeedbackRules.DefaultPriority(category);
        var topic = string.IsNullOrWhiteSpace(dto.Topic) ? null : dto.Topic.Trim()[..Math.Min(60, dto.Topic.Trim().Length)];

        var images = (dto.ImageUrls ?? []).Where(u => !string.IsNullOrWhiteSpace(u)).Take(6).ToList();
        var imagesJson = images.Count == 0 ? null : JsonSerializer.Serialize(images);
        while (imagesJson != null && imagesJson.Length > 2000 && images.Count > 0)
        {
            images.RemoveAt(images.Count - 1);
            imagesJson = images.Count == 0 ? null : JsonSerializer.Serialize(images);
        }

        var now = DateTime.Now;
        var monthStart = new DateTime(now.Year, now.Month, 1);
        var seq = await dbContext.Feedbacks.IgnoreQueryFilters()
            .CountAsync(f => f.StoreId == storeId && f.CreatedAt >= monthStart) + 1;

        var feedback = new Feedback
        {
            Id = Guid.NewGuid(),
            // Luôn lưu người gửi để hiện trong «Của tôi»; IsAnonymous quyết định ẩn với mọi người khác
            SenderEmployeeId = v.EmployeeId,
            IsAnonymous = dto.IsAnonymous,
            RecipientEmployeeId = dto.RecipientEmployeeId,
            Title = title,
            Content = content,
            Category = category,
            Topic = topic,
            Priority = priority,
            DueAt = FeedbackRules.DueFrom(now, priority),
            Code = FeedbackRules.MakeCode(now, seq),
            ImageUrls = imagesJson,
            Status = FeedbackRules.Pending,
            StoreId = storeId,
            IsActive = true,
            CreatedAt = now,
            CreatedBy = v.UserId,
        };
        dbContext.Feedbacks.Add(feedback);
        await dbContext.SaveChangesAsync();

        var senderLabel = dto.IsAnonymous ? "Ẩn danh" : await MyNameAsync(v.EmployeeId);
        await NotifyAsync(await HandlerUserIdsAsync(feedback), feedback,
            $"{FeedbackRules.CategoryName(category)} mới",
            $"{senderLabel}: {Label(feedback)} · mức độ {FeedbackRules.PriorityName(priority).ToLower()}");

        return Ok(AppResponse<object>.Success((await ToDtosAsync([feedback], v))[0]));
    }

    // ══════════════════ XỬ LÝ ══════════════════

    async Task<(Feedback? f, Viewer v, ActionResult? error)> LoadForAsync(Guid id, bool manage)
    {
        var v = await ViewerAsync();
        var f = await dbContext.Feedbacks.AsTracking()
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == RequiredStoreId && x.Deleted == null);
        if (f == null) return (null, v, NotFound(AppResponse<object>.Fail("Không tìm thấy phiếu")));
        if (!CanView(f, v) || (manage && !CanManage(f, v)))
            return (null, v, StatusCode(403, AppResponse<object>.Fail("Bạn không có quyền xử lý phiếu này")));
        return (f, v, null);
    }

    void ApplyStatus(Feedback f, string status, Guid? employeeId, DateTime now)
    {
        if (f.Status == FeedbackRules.Pending && status != FeedbackRules.Pending)
            f.FirstResponseAt ??= now;
        f.Status = status;
        if (status is FeedbackRules.Resolved or FeedbackRules.Closed)
        {
            f.ResolvedAt = now;
            f.RespondedAt ??= now;
            f.RespondedByEmployeeId ??= employeeId;
        }
        else
        {
            f.ResolvedAt = null;
        }
        f.UpdatedAt = now;
        f.UpdatedBy = CurrentUserId.ToString();
    }

    [HttpPatch("{id}/status")]
    [RequireModulePermission("Feedback", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<bool>>> UpdateStatus(Guid id, [FromBody] FeedbackStatusDto dto)
    {
        var (f, v, error) = await LoadForAsync(id, manage: true);
        if (error != null) return error;
        if (!FeedbackRules.Statuses.Contains(dto.Status))
            return BadRequest(AppResponse<bool>.Fail("Trạng thái không hợp lệ"));
        if (!FeedbackRules.CanHandlerMove(f!.Status, dto.Status))
            return Ok(AppResponse<bool>.Error(
                $"Không thể chuyển từ «{FeedbackRules.StatusName(f.Status)}» sang «{FeedbackRules.StatusName(dto.Status)}»"));

        var now = DateTime.Now;
        var from = f.Status;
        ApplyStatus(f, dto.Status, v.EmployeeId, now);
        var me = await MyNameAsync(v.EmployeeId);
        AddEvent(f, v.EmployeeId, $"{me} chuyển trạng thái: {FeedbackRules.StatusName(from)} → {FeedbackRules.StatusName(dto.Status)}");
        if (!string.IsNullOrWhiteSpace(dto.Note))
        {
            dbContext.FeedbackReplies.Add(new FeedbackReply
            {
                Id = Guid.NewGuid(), FeedbackId = f.Id, SenderEmployeeId = v.EmployeeId,
                Content = dto.Note.Trim(), IsFromSender = false, Kind = KindMessage,
                StoreId = f.StoreId, CreatedBy = v.UserId,
            });
            f.FirstResponseAt ??= now;
        }
        await dbContext.SaveChangesAsync();

        await NotifySenderAsync(f, "Cập nhật kiến nghị",
            $"{Label(f)}: {FeedbackRules.StatusName(dto.Status).ToLower()}"
            + (dto.Status == FeedbackRules.Resolved ? " — mời bạn đánh giá mức độ hài lòng" : ""));
        return Ok(AppResponse<bool>.Success(true));
    }

    /// <summary>Tương thích bản cũ: trả lời + đổi trạng thái trong 1 bước.</summary>
    [HttpPut("{id}/respond")]
    [RequireModulePermission("Feedback", ModulePermissionAction.View)]
    public Task<ActionResult<AppResponse<bool>>> Respond(Guid id, [FromBody] FeedbackRespondDto dto) =>
        UpdateStatus(id, new FeedbackStatusDto(dto.Status, dto.Response));

    /// <summary>Đổi mức độ / người xử lý / chủ đề / hạn xử lý.</summary>
    [HttpPatch("{id}/manage")]
    [RequireModulePermission("Feedback", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> Manage(Guid id, [FromBody] FeedbackManageDto dto)
    {
        var (f, v, error) = await LoadForAsync(id, manage: true);
        if (error != null) return error;
        var me = await MyNameAsync(v.EmployeeId);
        var now = DateTime.Now;
        var changed = false;
        Guid? newAssigneeUser = null;

        if (dto.Priority.HasValue && FeedbackRules.NormalizePriority(dto.Priority.Value) != f!.Priority)
        {
            var p = FeedbackRules.NormalizePriority(dto.Priority.Value);
            AddEvent(f, v.EmployeeId, $"{me} đổi mức độ: {FeedbackRules.PriorityName(f.Priority)} → {FeedbackRules.PriorityName(p)}");
            f.Priority = p;
            if (dto.DueAt == null && FeedbackRules.IsOpen(f.Status))
                f.DueAt = FeedbackRules.DueFrom(f.CreatedAt, p);
            changed = true;
        }
        if (dto.ClearAssignee && f!.AssigneeEmployeeId != null)
        {
            f.AssigneeEmployeeId = null;
            AddEvent(f, v.EmployeeId, $"{me} bỏ giao người xử lý");
            changed = true;
        }
        else if (dto.AssigneeEmployeeId.HasValue && dto.AssigneeEmployeeId != f!.AssigneeEmployeeId)
        {
            var emp = await dbContext.Employees
                .Where(e => e.Id == dto.AssigneeEmployeeId && e.StoreId == f.StoreId && e.Deleted == null)
                .Select(e => new { e.Id, Name = (e.LastName + " " + e.FirstName).Trim(), e.ApplicationUserId })
                .FirstOrDefaultAsync();
            if (emp == null) return Ok(AppResponse<object>.Error("Người xử lý không hợp lệ"));
            // Không giao phiếu cho chính người gửi (kể cả ẩn danh)
            if (f.SenderEmployeeId == emp.Id) return Ok(AppResponse<object>.Error("Không thể giao phiếu cho chính người gửi"));
            f.AssigneeEmployeeId = emp.Id;
            AddEvent(f, v.EmployeeId, $"{me} giao cho {emp.Name} xử lý");
            if (f.Status == FeedbackRules.Pending) ApplyStatus(f, FeedbackRules.InProgress, v.EmployeeId, now);
            newAssigneeUser = emp.ApplicationUserId;
            changed = true;
        }
        if (dto.Topic != null && dto.Topic.Trim() != (f!.Topic ?? ""))
        {
            f.Topic = string.IsNullOrWhiteSpace(dto.Topic) ? null : dto.Topic.Trim()[..Math.Min(60, dto.Topic.Trim().Length)];
            AddEvent(f, v.EmployeeId, $"{me} đổi chủ đề: {f.Topic ?? "(không)"}");
            changed = true;
        }
        if (dto.DueAt.HasValue && dto.DueAt != f!.DueAt)
        {
            f.DueAt = dto.DueAt;
            AddEvent(f, v.EmployeeId, $"{me} đặt hạn xử lý {dto.DueAt:dd/MM/yyyy HH:mm}");
            changed = true;
        }
        if (!changed) return Ok(AppResponse<object>.Success(true));

        f!.UpdatedAt = now;
        f.UpdatedBy = v.UserId;
        await dbContext.SaveChangesAsync();
        if (newAssigneeUser.HasValue)
            await NotifyAsync([newAssigneeUser.Value], f, "Bạn được giao xử lý kiến nghị",
                $"{Label(f)} · hạn {f.DueAt:dd/MM HH:mm}");
        return Ok(AppResponse<object>.Success(true));
    }

    /// <summary>Người gửi mở lại phiếu (chưa thoả đáng) trong 30 ngày sau khi giải quyết.</summary>
    [HttpPost("{id}/reopen")]
    [RequireModulePermission("Feedback", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<bool>>> Reopen(Guid id, [FromBody] FeedbackReopenDto dto)
    {
        var (f, v, error) = await LoadForAsync(id, manage: false);
        if (error != null) return error;
        if (!IsSender(f!, v)) return StatusCode(403, AppResponse<bool>.Fail("Chỉ người gửi được mở lại phiếu"));
        var now = DateTime.Now;
        if (!FeedbackRules.CanSenderReopen(f!.Status, f.ResolvedAt, now))
            return Ok(AppResponse<bool>.Error($"Chỉ mở lại được phiếu đã giải quyết trong {FeedbackRules.ReopenWindowDays} ngày"));

        ApplyStatus(f, FeedbackRules.InProgress, null, now);
        f.ReopenCount++;
        f.Rating = null;
        f.RatingComment = null;
        f.DueAt = now + FeedbackRules.SlaFor(f.Priority);
        AddEvent(f, null, "Người gửi mở lại phiếu");
        if (!string.IsNullOrWhiteSpace(dto.Reason))
            dbContext.FeedbackReplies.Add(new FeedbackReply
            {
                Id = Guid.NewGuid(), FeedbackId = f.Id, SenderEmployeeId = v.EmployeeId,
                Content = dto.Reason.Trim(), IsFromSender = true, Kind = KindMessage,
                StoreId = f.StoreId, CreatedBy = v.UserId,
            });
        await dbContext.SaveChangesAsync();
        await NotifyAsync(await HandlerUserIdsAsync(f), f, "Kiến nghị được mở lại",
            $"{Label(f)} — người gửi chưa hài lòng với kết quả");
        return Ok(AppResponse<bool>.Success(true));
    }

    /// <summary>Người gửi đánh giá mức độ hài lòng (1–5 sao) sau khi được giải quyết.</summary>
    [HttpPost("{id}/rate")]
    [RequireModulePermission("Feedback", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<bool>>> Rate(Guid id, [FromBody] FeedbackRateDto dto)
    {
        var (f, v, error) = await LoadForAsync(id, manage: false);
        if (error != null) return error;
        if (!IsSender(f!, v)) return StatusCode(403, AppResponse<bool>.Fail("Chỉ người gửi được đánh giá"));
        if (dto.Rating is < 1 or > 5) return Ok(AppResponse<bool>.Error("Đánh giá từ 1 đến 5 sao"));
        if (!FeedbackRules.CanSenderRate(f!.Status, f.Rating))
            return Ok(AppResponse<bool>.Error("Phiếu chưa được giải quyết hoặc đã đánh giá"));

        f.Rating = dto.Rating;
        f.RatingComment = string.IsNullOrWhiteSpace(dto.Comment) ? null : dto.Comment.Trim()[..Math.Min(1000, dto.Comment.Trim().Length)];
        f.UpdatedAt = DateTime.Now;
        AddEvent(f, null, $"Người gửi đánh giá {dto.Rating}/5 sao" + (f.RatingComment != null ? $": {f.RatingComment}" : ""));
        await dbContext.SaveChangesAsync();
        await NotifyAsync(await HandlerUserIdsAsync(f), f, "Đánh giá kiến nghị", $"{Label(f)}: {dto.Rating}/5 sao");
        return Ok(AppResponse<bool>.Success(true));
    }

    // ══════════════════ XOÁ ══════════════════

    [HttpDelete("{id}")]
    [RequireModulePermission("Feedback", ModulePermissionAction.Delete)]
    public async Task<ActionResult<AppResponse<bool>>> Delete(Guid id)
    {
        var (f, v, error) = await LoadForAsync(id, manage: false);
        if (error != null) return error;
        if (!IsAdmin)
        {
            if (!IsSender(f!, v)) return Ok(AppResponse<bool>.Error("Bạn không có quyền xoá phiếu này"));
            // Người gửi chỉ thu hồi khi phiếu chưa được tiếp nhận
            if (f!.Status != FeedbackRules.Pending)
                return Ok(AppResponse<bool>.Error("Phiếu đã được tiếp nhận — không thể thu hồi"));
        }
        f!.Deleted = DateTime.Now;
        f.DeletedBy = v.UserId;
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<bool>.Success(true));
    }

    // ══════════════════ NGƯỜI NHẬN / NGƯỜI XỬ LÝ ══════════════════

    /// <summary>Danh sách người có thể nhận / xử lý kiến nghị (quản lý, trưởng bộ phận, kế toán, giám đốc).</summary>
    [HttpGet("managers")]
    [RequireModulePermission("Feedback", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<object>>>> GetManagers() =>
        Ok(AppResponse<List<object>>.Success(await HandlersAsync(RequiredStoreId)));

    async Task<List<object>> HandlersAsync(Guid storeId)
    {
        var rows = await dbContext.Employees
            .Where(e => e.StoreId == storeId && e.Deleted == null && e.ApplicationUser != null
                        && e.ApplicationUser.IsActive && HandlerRoles.Contains(e.ApplicationUser.Role!))
            .OrderBy(e => e.LastName).ThenBy(e => e.FirstName)
            .Select(e => new
            {
                e.Id,
                Name = (e.LastName + " " + e.FirstName).Trim(),
                e.EmployeeCode,
                e.Position,
                e.Department,
                Role = e.ApplicationUser!.Role,
            })
            .ToListAsync();
        return rows.Cast<object>().ToList();
    }

    // ══════════════════ ẢNH ══════════════════

    static readonly string[] ImageExts = [".jpg", ".jpeg", ".png", ".gif", ".webp"];

    async Task<(string filePath, string fileUrl)> SaveImageAsync(IFormFile file)
    {
        var storeFolder = await GetStoreFolderAsync("uploads/feedback");
        await using var raw = file.OpenReadStream();
        var (optimized, uploadName, _) = await ImageOptimizeHelper.OptimizeAsync(
            raw, file.FileName, ImageOptimizeHelper.PhotoMaxEdge, ImageOptimizeHelper.PhotoJpegQuality);
        await using (optimized)
        {
            var filePath = await fileStorageService.UploadAsync(optimized, uploadName, storeFolder);
            return (filePath, fileStorageService.GetFileUrl(filePath));
        }
    }

    [HttpPost("upload-image")]
    [RequireModulePermission("Feedback", ModulePermissionAction.Create)]
    [RequestSizeLimit(10_000_000)]
    public async Task<ActionResult<AppResponse<object>>> UploadImage(IFormFile file)
    {
        if (file == null || file.Length == 0) return BadRequest(AppResponse<object>.Fail("Chưa chọn file"));
        if (!ImageExts.Contains(Path.GetExtension(file.FileName).ToLowerInvariant()))
            return BadRequest(AppResponse<object>.Fail("Chỉ hỗ trợ ảnh JPG, PNG, GIF, WEBP"));
        try
        {
            var (filePath, fileUrl) = await SaveImageAsync(file);
            return Ok(AppResponse<object>.Success(new { filePath, fileUrl }));
        }
        catch
        {
            return StatusCode(500, AppResponse<object>.Fail("Không thể tải ảnh lên"));
        }
    }

    // ══════════════════ CHI TIẾT + TRAO ĐỔI ══════════════════

    [HttpGet("{id}/replies")]
    [RequireModulePermission("Feedback", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> GetReplies(Guid id)
    {
        var (f, v, error) = await LoadForAsync(id, manage: false);
        if (error != null) return error;
        var canManage = CanManage(f!, v);
        var mine = IsSender(f!, v);

        var rows = await dbContext.FeedbackReplies
            .Where(r => r.FeedbackId == id && (canManage || r.Kind != KindInternal))
            .OrderBy(r => r.CreatedAt)
            .ToListAsync();
        var emps = await EmployeesAsync(rows.Select(r => r.SenderEmployeeId));
        var users = await UserNamesAsync(rows.Select(r => r.CreatedBy));

        var replies = rows.Select(r =>
        {
            var hide = f!.IsAnonymous && r.IsFromSender && !mine;
            var name = hide ? null
                : (r.SenderEmployeeId.HasValue ? emps.GetValueOrDefault(r.SenderEmployeeId.Value)?.Name : null)
                  ?? users.GetValueOrDefault(r.CreatedBy ?? "");
            return new FeedbackReplyDto(
                r.Id, r.FeedbackId, r.Content, ParseImageUrls(r.ImageUrls), r.IsFromSender,
                name, hide ? null : r.SenderEmployeeId, r.CreatedAt,
                (v.EmployeeId.HasValue && r.SenderEmployeeId == v.EmployeeId && r.Kind != KindEvent) || (r.CreatedBy == v.UserId && r.Kind != KindEvent),
                r.Kind);
        }).ToList();

        var handlers = canManage ? await HandlersAsync(f!.StoreId ?? RequiredStoreId) : [];

        var now = DateTime.Now;
        return Ok(AppResponse<object>.Success(new
        {
            feedback = (await ToDtosAsync([f!], v))[0],
            replies,
            handlers,
            topics = FeedbackRules.Topics,
            viewerContext = new
            {
                canReply = f!.Status != FeedbackRules.Closed || canManage,
                canManage,
                isOriginalSender = mine,
                canRate = mine && FeedbackRules.CanSenderRate(f.Status, f.Rating),
                canReopen = mine && FeedbackRules.CanSenderReopen(f.Status, f.ResolvedAt, now),
                canWithdraw = mine && f.Status == FeedbackRules.Pending,
                employeeId = v.EmployeeId,
            },
        }));
    }

    [HttpPost("{id}/replies")]
    [RequireModulePermission("Feedback", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<FeedbackReplyDto>>> CreateReply(Guid id, [FromBody] FeedbackReplyCreateDto dto)
    {
        var (f, v, error) = await LoadForAsync(id, manage: false);
        if (error != null) return error;
        var content = dto.Content?.Trim() ?? "";
        if (content.Length == 0) return Ok(AppResponse<FeedbackReplyDto>.Error("Nội dung trống"));
        if (content.Length > 5000) content = content[..5000];

        var canManage = CanManage(f!, v);
        var isSender = IsSender(f!, v);
        if (f!.Status == FeedbackRules.Closed && !canManage)
            return Ok(AppResponse<FeedbackReplyDto>.Error("Phiếu đã đóng — hãy mở lại nếu chưa được giải quyết thoả đáng"));
        if (dto.Internal && !canManage)
            return StatusCode(403, AppResponse<FeedbackReplyDto>.Fail("Chỉ người xử lý được ghi chú nội bộ"));

        var now = DateTime.Now;
        var reply = new FeedbackReply
        {
            Id = Guid.NewGuid(),
            FeedbackId = id,
            SenderEmployeeId = v.EmployeeId,
            Content = content,
            IsFromSender = isSender,
            Kind = dto.Internal ? KindInternal : KindMessage,
            StoreId = f.StoreId,
            CreatedBy = v.UserId,
            CreatedAt = now,
        };
        dbContext.FeedbackReplies.Add(reply);

        if (!isSender && !dto.Internal)
        {
            f.FirstResponseAt ??= now;
            if (f.Status == FeedbackRules.Pending) ApplyStatus(f, FeedbackRules.InProgress, v.EmployeeId, now);
        }
        f.UpdatedAt = now;
        f.UpdatedBy = v.UserId;
        await dbContext.SaveChangesAsync();

        var preview = content.Length > 100 ? content[..100] + "…" : content;
        var myName = isSender && f.IsAnonymous ? "Ẩn danh" : await MyNameAsync(v.EmployeeId);
        if (dto.Internal)
            await NotifyAsync(await HandlerUserIdsAsync(f), f, "Ghi chú nội bộ", $"{myName} · {Label(f)}: \"{preview}\"");
        else if (isSender)
            await NotifyAsync(await HandlerUserIdsAsync(f), f, "Phản hồi mới", $"{myName}: \"{preview}\"");
        else
            await NotifySenderAsync(f, "Phản hồi kiến nghị", $"{myName}: \"{preview}\"");

        return Ok(AppResponse<FeedbackReplyDto>.Success(new FeedbackReplyDto(
            reply.Id, reply.FeedbackId, reply.Content, null, reply.IsFromSender,
            isSender && f.IsAnonymous ? null : myName, isSender && f.IsAnonymous ? null : v.EmployeeId,
            reply.CreatedAt, true, reply.Kind)));
    }

    [HttpPost("{id}/replies/{replyId}/image")]
    [RequireModulePermission("Feedback", ModulePermissionAction.View)]
    [RequestSizeLimit(10_000_000)]
    public async Task<ActionResult<AppResponse<object>>> UploadReplyImage(Guid id, Guid replyId, IFormFile file)
    {
        if (file == null || file.Length == 0) return BadRequest(AppResponse<object>.Fail("Chưa chọn file"));
        var (f, v, error) = await LoadForAsync(id, manage: false);
        if (error != null) return error;
        var reply = await dbContext.FeedbackReplies.AsTracking()
            .FirstOrDefaultAsync(r => r.Id == replyId && r.FeedbackId == f!.Id);
        if (reply == null) return NotFound(AppResponse<object>.Fail("Không tìm thấy phản hồi"));
        if (reply.CreatedBy != v.UserId) return StatusCode(403, AppResponse<object>.Fail("Không có quyền"));
        if (!ImageExts.Contains(Path.GetExtension(file.FileName).ToLowerInvariant()))
            return BadRequest(AppResponse<object>.Fail("Chỉ hỗ trợ ảnh JPG, PNG, GIF, WEBP"));
        try
        {
            var (filePath, fileUrl) = await SaveImageAsync(file);
            var urls = ParseImageUrls(reply.ImageUrls) ?? [];
            urls.Add(fileUrl);
            reply.ImageUrls = JsonSerializer.Serialize(urls);
            await dbContext.SaveChangesAsync();
            return Ok(AppResponse<object>.Success(new { filePath, fileUrl, imageUrls = urls }));
        }
        catch
        {
            return StatusCode(500, AppResponse<object>.Fail("Không thể tải ảnh lên"));
        }
    }

    // ══════════════════ BÁO CÁO ══════════════════

    /// <summary>
    /// Báo cáo kiến nghị / khiếu nại: số lượng theo trạng thái / loại / chủ đề / mức độ / bộ phận,
    /// xu hướng theo tháng, tỷ lệ đúng hạn, thời gian phản hồi / giải quyết, mức hài lòng, hiệu quả người xử lý.
    /// </summary>
    [HttpGet("stats")]
    [RequireModulePermission("Feedback", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> GetStats([FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate)
    {
        var storeId = RequiredStoreId;
        var v = await ViewerAsync();
        if (!v.Handler) return StatusCode(403, AppResponse<object>.Fail("Chỉ người xử lý được xem báo cáo"));

        var now = DateTime.Now;
        var to = (toDate ?? now).Date.AddDays(1);
        var from = (fromDate ?? now.Date.AddMonths(-5).AddDays(1 - now.Day)).Date;
        var list = await Scoped(storeId, v).Where(f => f.CreatedAt >= from && f.CreatedAt < to).ToListAsync();
        var emps = await EmployeesAsync(list.SelectMany(f => new[] { f.SenderEmployeeId, f.AssigneeEmployeeId, f.RespondedByEmployeeId }));

        static double? Avg(IEnumerable<double> xs) { var a = xs.ToList(); return a.Count == 0 ? null : Math.Round(a.Average(), 1); }
        var closed = list.Where(f => f.ResolvedAt.HasValue).ToList();
        var onTime = closed.Count(f => !f.DueAt.HasValue || f.ResolvedAt <= f.DueAt);

        var months = new List<DateTime>();
        for (var m = new DateTime(from.Year, from.Month, 1); m < to; m = m.AddMonths(1)) months.Add(m);

        Guid? HandlerOf(Feedback f) => f.AssigneeEmployeeId ?? f.RespondedByEmployeeId ?? f.RecipientEmployeeId;

        return Ok(AppResponse<object>.Success(new
        {
            from,
            to = to.AddDays(-1),
            totals = new
            {
                total = list.Count,
                open = list.Count(f => FeedbackRules.IsOpen(f.Status)),
                pending = list.Count(f => f.Status == FeedbackRules.Pending),
                inProgress = list.Count(f => f.Status == FeedbackRules.InProgress),
                resolved = list.Count(f => f.Status == FeedbackRules.Resolved),
                closed = list.Count(f => f.Status == FeedbackRules.Closed),
                overdue = list.Count(f => FeedbackRules.IsOverdue(f.Status, f.DueAt, now)),
                complaints = list.Count(f => f.Category == "Complaint"),
                anonymous = list.Count(f => f.IsAnonymous),
                reopened = list.Count(f => f.ReopenCount > 0),
                onTimePct = closed.Count == 0 ? (double?)null : Math.Round(onTime * 100.0 / closed.Count, 1),
                avgFirstResponseHours = Avg(list.Where(f => f.FirstResponseAt.HasValue)
                    .Select(f => (f.FirstResponseAt!.Value - f.CreatedAt).TotalHours)),
                avgResolveHours = Avg(closed.Select(f => (f.ResolvedAt!.Value - f.CreatedAt).TotalHours)),
                avgRating = Avg(list.Where(f => f.Rating.HasValue).Select(f => (double)f.Rating!.Value)),
                rated = list.Count(f => f.Rating.HasValue),
            },
            byStatus = FeedbackRules.Statuses.Select(s => new
            {
                code = s, name = FeedbackRules.StatusName(s), count = list.Count(f => f.Status == s),
            }),
            byCategory = list.GroupBy(f => f.Category).Select(g => new
            {
                code = g.Key, name = FeedbackRules.CategoryName(g.Key), count = g.Count(),
                open = g.Count(f => FeedbackRules.IsOpen(f.Status)),
            }).OrderByDescending(x => x.count),
            byTopic = list.GroupBy(f => f.Topic ?? "Chưa phân chủ đề").Select(g => new
            {
                name = g.Key, count = g.Count(), open = g.Count(f => FeedbackRules.IsOpen(f.Status)),
                complaints = g.Count(f => f.Category == "Complaint"),
            }).OrderByDescending(x => x.count),
            byPriority = Enumerable.Range(0, 4).Reverse().Select(p => new
            {
                priority = p, name = FeedbackRules.PriorityName(p), count = list.Count(f => f.Priority == p),
                overdue = list.Count(f => f.Priority == p && FeedbackRules.IsOverdue(f.Status, f.DueAt, now)),
            }),
            // Bộ phận người gửi — phiếu ẩn danh gom riêng, không suy ra bộ phận
            byDepartment = list.GroupBy(f => f.IsAnonymous ? "Ẩn danh"
                    : f.SenderEmployeeId.HasValue && emps.TryGetValue(f.SenderEmployeeId.Value, out var e) && !string.IsNullOrWhiteSpace(e.Department)
                        ? e.Department! : "Chưa phân phòng")
                .Select(g => new { name = g.Key, count = g.Count(), complaints = g.Count(f => f.Category == "Complaint") })
                .OrderByDescending(x => x.count),
            byMonth = months.Select(m => new
            {
                month = m.ToString("MM/yyyy"),
                received = list.Count(f => f.CreatedAt >= m && f.CreatedAt < m.AddMonths(1)),
                resolved = list.Count(f => f.ResolvedAt >= m && f.ResolvedAt < m.AddMonths(1)),
                complaints = list.Count(f => f.Category == "Complaint" && f.CreatedAt >= m && f.CreatedAt < m.AddMonths(1)),
            }),
            handlers = list.Where(f => HandlerOf(f).HasValue).GroupBy(f => HandlerOf(f)!.Value).Select(g =>
            {
                var done = g.Where(f => f.ResolvedAt.HasValue).ToList();
                return new
                {
                    name = emps.GetValueOrDefault(g.Key)?.Name ?? "",
                    total = g.Count(),
                    open = g.Count(f => FeedbackRules.IsOpen(f.Status)),
                    resolved = done.Count,
                    overdue = g.Count(f => FeedbackRules.IsOverdue(f.Status, f.DueAt, now)),
                    onTimePct = done.Count == 0 ? (double?)null
                        : Math.Round(done.Count(f => !f.DueAt.HasValue || f.ResolvedAt <= f.DueAt) * 100.0 / done.Count, 1),
                    avgResolveHours = Avg(done.Select(f => (f.ResolvedAt!.Value - f.CreatedAt).TotalHours)),
                    avgRating = Avg(g.Where(f => f.Rating.HasValue).Select(f => (double)f.Rating!.Value)),
                };
            }).OrderByDescending(x => x.total),
            oldestOpen = list.Where(f => FeedbackRules.IsOpen(f.Status))
                .OrderByDescending(f => FeedbackRules.IsOverdue(f.Status, f.DueAt, now))
                .ThenByDescending(f => f.Priority).ThenBy(f => f.CreatedAt).Take(10)
                .Select(f => new
                {
                    id = f.Id, code = f.Code, title = f.Title, priority = f.Priority,
                    priorityName = FeedbackRules.PriorityName(f.Priority),
                    status = f.Status, statusName = FeedbackRules.StatusName(f.Status),
                    ageDays = (int)(now - f.CreatedAt).TotalDays,
                    dueAt = f.DueAt, overdue = FeedbackRules.IsOverdue(f.Status, f.DueAt, now),
                    assignee = f.AssigneeEmployeeId.HasValue ? emps.GetValueOrDefault(f.AssigneeEmployeeId.Value)?.Name : null,
                }),
        }));
    }

    // ══════════════════ HELPERS ══════════════════

    private async Task<string> GetStoreFolderAsync(string subfolder)
    {
        var storeId = CurrentStoreId;
        if (storeId.HasValue)
        {
            var storeCode = await dbContext.Stores.Where(s => s.Id == storeId.Value).Select(s => s.Code).FirstOrDefaultAsync();
            if (!string.IsNullOrEmpty(storeCode)) return $"stores/{storeCode}/{subfolder}";
        }
        return subfolder;
    }

    private static List<string>? ParseImageUrls(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return null;
        try { return JsonSerializer.Deserialize<List<string>>(json); }
        catch { return null; }
    }
}

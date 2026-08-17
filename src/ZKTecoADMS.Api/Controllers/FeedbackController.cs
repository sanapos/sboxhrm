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
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
public class FeedbackController(
    ZKTecoDbContext dbContext,
    ISystemNotificationService notificationService,
    IFileStorageService fileStorageService) : AuthenticatedControllerBase
{
    #region DTOs

    public record FeedbackDto(
        Guid Id, string Title, string Content, string Category, string Status,
        bool IsAnonymous, string? SenderName, string? SenderCode,
        Guid? SenderEmployeeId, Guid? RecipientEmployeeId,
        string? RecipientName, string? Response,
        string? RespondedByName, DateTime? RespondedAt,
        DateTime CreatedAt, List<string>? ImageUrls = null, int ReplyCount = 0);

    public record FeedbackCreateDto(
        string Title, string Content, string Category,
        bool IsAnonymous, Guid? RecipientEmployeeId);

    public record FeedbackRespondDto(string Response, string Status);

    public record FeedbackStatusDto(string Status);

    public record FeedbackReplyDto(
        Guid Id, Guid FeedbackId, string Content, List<string>? ImageUrls,
        bool IsFromSender, string? SenderName, Guid? SenderEmployeeId,
        DateTime CreatedAt, bool IsMine = false);

    public record FeedbackReplyCreateDto(string Content);

    #endregion

    /// <summary>
    /// Lấy EmployeeId hiện tại, nếu null thì tìm Employee qua ApplicationUserId
    /// </summary>
    private async Task<Guid?> ResolveEmployeeIdAsync()
    {
        var empId = EmployeeId;
        if (empId.HasValue) return empId;

        // Fallback: tìm Employee theo ApplicationUserId
        var userId = CurrentUserId;
        var employee = await dbContext.Employees
            .Where(e => e.ApplicationUserId == userId && e.Deleted == null)
            .Select(e => e.Id)
            .FirstOrDefaultAsync();

        return employee == default ? null : employee;
    }

    /// <summary>
    /// Lấy tên Employee theo Id, fallback tên user nếu không tìm thấy
    /// </summary>
    private async Task<string?> GetEmployeeNameAsync(Guid? employeeId)
    {
        if (!employeeId.HasValue) return null;
        return await dbContext.Employees
            .Where(e => e.Id == employeeId.Value)
            .Select(e => (e.LastName + " " + e.FirstName).Trim())
            .FirstOrDefaultAsync();
    }

    /// <summary>
    /// Resolve Application User Id for push/in-app notifications.
    /// Falls back to CreatedBy user id when Employee.ApplicationUserId is not linked.
    /// </summary>
    private async Task<Guid?> ResolveUserIdForEmployeeAsync(
        Guid? employeeId, string? createdByUserId = null)
    {
        if (employeeId.HasValue)
        {
            var linkedUserId = await dbContext.Employees
                .Where(e => e.Id == employeeId.Value && e.ApplicationUserId != null)
                .Select(e => e.ApplicationUserId!.Value)
                .FirstOrDefaultAsync();
            if (linkedUserId != Guid.Empty)
                return linkedUserId;
        }

        if (!string.IsNullOrWhiteSpace(createdByUserId)
            && Guid.TryParse(createdByUserId, out var uid))
        {
            var exists = await dbContext.Users.AnyAsync(u => u.Id == uid);
            if (exists) return uid;
        }

        return null;
    }

    private async Task<string?> ResolveDisplayNameAsync(
        Guid? employeeId, string? createdByUserId = null)
    {
        var empName = await GetEmployeeNameAsync(employeeId);
        if (!string.IsNullOrWhiteSpace(empName)) return empName;

        if (!string.IsNullOrWhiteSpace(createdByUserId)
            && Guid.TryParse(createdByUserId, out var uid))
        {
            var userName = await dbContext.Users
                .Where(u => u.Id == uid)
                .Select(u => ((u.LastName ?? "") + " " + (u.FirstName ?? "")).Trim())
                .FirstOrDefaultAsync();
            if (!string.IsNullOrWhiteSpace(userName)) return userName;
        }

        return null;
    }

    private async Task<List<Guid>> ResolveFeedbackManagerNotifyUserIdsAsync(
        Feedback feedback, Guid excludeUserId)
    {
        var targets = new HashSet<Guid>();

        if (feedback.RecipientEmployeeId.HasValue)
        {
            var uid = await ResolveUserIdForEmployeeAsync(feedback.RecipientEmployeeId);
            if (uid.HasValue) targets.Add(uid.Value);
        }

        var replierUserIds = await dbContext.FeedbackReplies
            .Where(r => r.FeedbackId == feedback.Id && !r.IsFromSender && r.CreatedBy != null)
            .Select(r => r.CreatedBy!)
            .Distinct()
            .ToListAsync();
        foreach (var s in replierUserIds)
        {
            if (Guid.TryParse(s, out var uid)) targets.Add(uid);
        }

        if (!feedback.RecipientEmployeeId.HasValue)
        {
            var adminIds = await dbContext.Users
                .Where(u => u.IsActive && u.StoreId == feedback.StoreId &&
                    (u.Role == "Admin" || u.Role == "SuperAdmin" ||
                     u.Role == "Manager" || u.Role == "StoreOwner" || u.Role == "Director"))
                .Select(u => u.Id)
                .ToListAsync();
            foreach (var id in adminIds) targets.Add(id);
        }

        targets.Remove(excludeUserId);
        return targets.ToList();
    }

    private async Task NotifyFeedbackReplyAsync(
        Feedback feedback, string senderLabel, string preview, bool isSender)
    {
        var targets = new HashSet<Guid>();

        if (isSender)
        {
            foreach (var id in await ResolveFeedbackManagerNotifyUserIdsAsync(feedback, CurrentUserId))
                targets.Add(id);
        }
        else
        {
            var senderUid = await ResolveUserIdForEmployeeAsync(
                feedback.SenderEmployeeId, feedback.CreatedBy);
            if (senderUid.HasValue && senderUid.Value != CurrentUserId)
                targets.Add(senderUid.Value);
        }

        if (targets.Count == 0) return;

        await notificationService.CreateAndSendToUsersAsync(
            targets.ToList(), NotificationType.Info,
            "Phản hồi mới",
            $"{senderLabel}: \"{preview}\"",
            relatedEntityType: "Feedback", relatedEntityId: feedback.Id,
            fromUserId: CurrentUserId, categoryCode: "feedback", storeId: feedback.StoreId);
    }

    private async Task NotifyFeedbackApproversNewItemAsync(
        Feedback feedback, string senderLabel)
    {
        if (feedback.RecipientEmployeeId.HasValue) return;

        var targets = await ResolveFeedbackManagerNotifyUserIdsAsync(feedback, CurrentUserId);
        if (targets.Count == 0) return;

        await notificationService.CreateAndSendToUsersAsync(
            targets, NotificationType.Info,
            "Phản ánh mới",
            $"Phản ánh từ {senderLabel}: \"{feedback.Title}\"",
            relatedEntityType: "Feedback", relatedEntityId: feedback.Id,
            fromUserId: CurrentUserId, categoryCode: "feedback", storeId: feedback.StoreId);
    }

    private bool IsOriginalFeedbackSender(Feedback feedback, Guid? employeeId) =>
        feedback.SenderEmployeeId == employeeId
        || feedback.CreatedBy == CurrentUserId.ToString();

    private async Task<bool> IsFeedbackRecipientAsync(Feedback feedback, Guid? employeeId)
    {
        if (feedback.RecipientEmployeeId == employeeId) return true;
        if (!feedback.RecipientEmployeeId.HasValue) return false;

        var recipientUserId = await dbContext.Employees
            .Where(e => e.Id == feedback.RecipientEmployeeId.Value
                && e.ApplicationUserId != null)
            .Select(e => e.ApplicationUserId!.Value)
            .FirstOrDefaultAsync();
        return recipientUserId != Guid.Empty && recipientUserId == CurrentUserId;
    }

    private async Task<bool> CanAccessFeedbackAsync(Feedback feedback, Guid? employeeId)
    {
        if (IsAdmin || IsManager) return true;
        if (IsOriginalFeedbackSender(feedback, employeeId)) return true;
        if (await IsFeedbackRecipientAsync(feedback, employeeId)) return true;
        return false;
    }

    private async Task<bool> CanReplyToFeedbackAsync(Feedback feedback, Guid? employeeId)
    {
        if (feedback.Status == "Closed") return false;
        return await CanAccessFeedbackAsync(feedback, employeeId);
    }

    private static bool IsReplyFromCurrentUser(
        Guid? replySenderEmployeeId, string? replyCreatedBy,
        Guid? viewerEmployeeId, Guid currentUserId)
    {
        if (viewerEmployeeId.HasValue && replySenderEmployeeId == viewerEmployeeId)
            return true;
        return replyCreatedBy == currentUserId.ToString();
    }

    // ══════════════════ GET ALL (Manager/Admin) ══════════════════

    private static IQueryable<Feedback> ApplyFeedbackListFilters(
        IQueryable<Feedback> query,
        string? status,
        string? category,
        Guid? senderEmployeeId,
        Guid? recipientEmployeeId,
        bool? generalMailboxOnly,
        DateTime? fromDate,
        DateTime? toDate)
    {
        if (!string.IsNullOrEmpty(status))
            query = query.Where(f => f.Status == status);
        if (!string.IsNullOrEmpty(category))
            query = query.Where(f => f.Category == category);
        if (senderEmployeeId.HasValue)
            query = query.Where(f => f.SenderEmployeeId == senderEmployeeId);
        if (generalMailboxOnly == true)
            query = query.Where(f => f.RecipientEmployeeId == null);
        else if (recipientEmployeeId.HasValue)
            query = query.Where(f => f.RecipientEmployeeId == recipientEmployeeId);
        if (fromDate.HasValue)
        {
            var from = fromDate.Value.Date;
            query = query.Where(f => f.CreatedAt >= from);
        }
        if (toDate.HasValue)
        {
            var toExclusive = toDate.Value.Date.AddDays(1);
            query = query.Where(f => f.CreatedAt < toExclusive);
        }
        return query;
    }

    [HttpGet]
    [RequireModulePermission("Feedback", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> GetAll(
        [FromQuery] string? status, [FromQuery] string? category,
        [FromQuery] Guid? senderEmployeeId, [FromQuery] Guid? recipientEmployeeId,
        [FromQuery] bool? generalMailboxOnly,
        [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate,
        [FromQuery] int page = 1, [FromQuery] int pageSize = 20)
    {
        var storeId = RequiredStoreId;
        var employeeId = await ResolveEmployeeIdAsync();

        var query = dbContext.Feedbacks
            .Where(f => f.StoreId == storeId && f.Deleted == null);

        if (IsAdmin)
        {
            // Admin thấy tất cả phản ánh trong cửa hàng
        }
        else if (IsManager)
        {
            query = query.Where(f =>
                f.RecipientEmployeeId == employeeId || f.RecipientEmployeeId == null);
        }
        else
        {
            // NV thường: hòm thư chung + phản ánh gửi trực tiếp tới mình
            query = query.Where(f =>
                f.RecipientEmployeeId == null || f.RecipientEmployeeId == employeeId);
        }

        query = ApplyFeedbackListFilters(
            query, status, category, senderEmployeeId, recipientEmployeeId,
            generalMailboxOnly, fromDate, toDate);

        var total = await query.CountAsync();
        var rawItems = await query
            .OrderByDescending(f => f.CreatedAt)
            .Skip((page - 1) * pageSize).Take(pageSize)
            .Select(f => new
            {
                f.Id, f.Title, f.Content, f.Category, f.Status,
                f.IsAnonymous, f.SenderEmployeeId, f.RecipientEmployeeId,
                f.ImageUrls,
                SenderName = f.SenderEmployee != null
                    ? (f.SenderEmployee.LastName + " " + f.SenderEmployee.FirstName).Trim() : null,
                SenderCode = f.SenderEmployee != null ? f.SenderEmployee.EmployeeCode : null,
                RecipientName = f.RecipientEmployee != null
                    ? (f.RecipientEmployee.LastName + " " + f.RecipientEmployee.FirstName).Trim() : null,
                f.Response,
                RespondedByName = f.RespondedByEmployee != null
                    ? (f.RespondedByEmployee.LastName + " " + f.RespondedByEmployee.FirstName).Trim() : null,
                f.RespondedByEmployeeId,
                f.RespondedAt,
                f.CreatedAt,
                f.CreatedBy,
                f.UpdatedBy,
                ReplyCount = f.Replies.Count,
            })
            .ToListAsync();

        // Resolve names for items where Employee navigation was null (user without Employee record)
        var needSenderResolve = rawItems
            .Where(i => !i.IsAnonymous && i.SenderName == null && i.SenderEmployeeId.HasValue)
            .Select(i => i.SenderEmployeeId!.Value).Distinct().ToList();
        var needRespResolve = rawItems
            .Where(i => i.RespondedByName == null && i.RespondedByEmployeeId.HasValue)
            .Select(i => i.RespondedByEmployeeId!.Value).Distinct().ToList();
        var allIdsToResolve = needSenderResolve.Union(needRespResolve).ToList();

        var resolvedNames = allIdsToResolve.Count > 0
            ? await dbContext.Employees.IgnoreQueryFilters()
                .Where(e => allIdsToResolve.Contains(e.Id))
                .ToDictionaryAsync(e => e.Id, e => (e.LastName + " " + e.FirstName).Trim())
            : new Dictionary<Guid, string>();

        // Resolve from UserId (CreatedBy / UpdatedBy) for users without Employee
        var needUserResolve = rawItems
            .Where(i => !i.IsAnonymous && i.SenderName == null && !i.SenderEmployeeId.HasValue
                && !string.IsNullOrEmpty(i.CreatedBy))
            .Select(i => i.CreatedBy!)
            .Union(rawItems
                .Where(i => i.RespondedByName == null && !i.RespondedByEmployeeId.HasValue
                    && i.Response != null && !string.IsNullOrEmpty(i.UpdatedBy))
                .Select(i => i.UpdatedBy!))
            .Distinct().ToList();
        var userNames = needUserResolve.Count > 0
            ? await dbContext.Users
                .Where(u => needUserResolve.Contains(u.Id.ToString()))
                .ToDictionaryAsync(u => u.Id.ToString(), u => ((u.LastName ?? "") + " " + (u.FirstName ?? "")).Trim())
            : new Dictionary<string, string>();

        var items = rawItems.Select(f => new FeedbackDto(
            f.Id, f.Title, f.Content, f.Category, f.Status,
            f.IsAnonymous,
            f.IsAnonymous ? null : (f.SenderName
                ?? (f.SenderEmployeeId.HasValue && resolvedNames.TryGetValue(f.SenderEmployeeId.Value, out var sn) ? sn : null)
                ?? (f.CreatedBy != null && userNames.TryGetValue(f.CreatedBy, out var un) ? un : null)),
            f.IsAnonymous ? null : (f.SenderCode),
            f.IsAnonymous ? null : f.SenderEmployeeId,
            f.RecipientEmployeeId,
            f.RecipientName,
            f.Response,
            f.RespondedByName
                ?? (f.RespondedByEmployeeId.HasValue && resolvedNames.TryGetValue(f.RespondedByEmployeeId.Value, out var rn) ? rn : null)
                ?? (f.Response != null && f.UpdatedBy != null && userNames.TryGetValue(f.UpdatedBy, out var respUserName) ? respUserName : null),
            f.RespondedAt,
            f.CreatedAt,
            ParseImageUrls(f.ImageUrls),
            f.ReplyCount
        )).ToList();

        return Ok(AppResponse<object>.Success(new { items, total, page, pageSize }));
    }

    // ══════════════════ GET MY FEEDBACKS ══════════════════

    [HttpGet("my")]
    [RequireModulePermission("Feedback", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<FeedbackDto>>>> GetMyFeedbacks(
        [FromQuery] string? status, [FromQuery] string? category,
        [FromQuery] Guid? senderEmployeeId, [FromQuery] Guid? recipientEmployeeId,
        [FromQuery] bool? generalMailboxOnly,
        [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate)
    {
        var storeId = RequiredStoreId;
        var employeeId = await ResolveEmployeeIdAsync();
        var userId = CurrentUserId.ToString();

        var query = dbContext.Feedbacks
            .Where(f => f.StoreId == storeId && f.Deleted == null
                && (f.SenderEmployeeId == employeeId
                    || f.CreatedBy == userId
                    || f.RecipientEmployeeId == employeeId));

        query = ApplyFeedbackListFilters(
            query, status, category, senderEmployeeId, recipientEmployeeId,
            generalMailboxOnly, fromDate, toDate);

        var rawItems = await query
            .OrderByDescending(f => f.CreatedAt)
            .Select(f => new
            {
                f.Id, f.Title, f.Content, f.Category, f.Status,
                f.IsAnonymous, f.SenderEmployeeId, f.RecipientEmployeeId,
                f.ImageUrls,
                RecipientName = f.RecipientEmployee != null
                    ? (f.RecipientEmployee.LastName + " " + f.RecipientEmployee.FirstName).Trim() : null,
                f.Response,
                RespondedByName = f.RespondedByEmployee != null
                    ? (f.RespondedByEmployee.LastName + " " + f.RespondedByEmployee.FirstName).Trim() : null,
                f.RespondedByEmployeeId,
                f.RespondedAt, f.CreatedAt,
                f.UpdatedBy,
                ReplyCount = f.Replies.Count,
            })
            .ToListAsync();

        // Resolve responder names if missing
        var needRespResolve = rawItems
            .Where(i => i.RespondedByName == null && i.RespondedByEmployeeId.HasValue)
            .Select(i => i.RespondedByEmployeeId!.Value).Distinct().ToList();
        var resolvedNames = needRespResolve.Count > 0
            ? await dbContext.Employees.IgnoreQueryFilters()
                .Where(e => needRespResolve.Contains(e.Id))
                .ToDictionaryAsync(e => e.Id, e => (e.LastName + " " + e.FirstName).Trim())
            : new Dictionary<Guid, string>();

        // Resolve responder from UserId for users without Employee
        var needUserResolve = rawItems
            .Where(i => i.RespondedByName == null && !i.RespondedByEmployeeId.HasValue
                && i.Response != null && !string.IsNullOrEmpty(i.UpdatedBy))
            .Select(i => i.UpdatedBy!).Distinct().ToList();
        var userNames = needUserResolve.Count > 0
            ? await dbContext.Users
                .Where(u => needUserResolve.Contains(u.Id.ToString()))
                .ToDictionaryAsync(u => u.Id.ToString(), u => ((u.LastName ?? "") + " " + (u.FirstName ?? "")).Trim())
            : new Dictionary<string, string>();

        var items = rawItems.Select(f => new FeedbackDto(
            f.Id, f.Title, f.Content, f.Category, f.Status,
            f.IsAnonymous,
            null, null, f.SenderEmployeeId,
            f.RecipientEmployeeId, f.RecipientName,
            f.Response,
            f.RespondedByName
                ?? (f.RespondedByEmployeeId.HasValue && resolvedNames.TryGetValue(f.RespondedByEmployeeId.Value, out var rn) ? rn : null)
                ?? (f.Response != null && f.UpdatedBy != null && userNames.TryGetValue(f.UpdatedBy, out var run) ? run : null),
            f.RespondedAt, f.CreatedAt,
            ParseImageUrls(f.ImageUrls),
            f.ReplyCount
        )).ToList();

        return Ok(AppResponse<List<FeedbackDto>>.Success(items));
    }

    // ══════════════════ CREATE ══════════════════

    [HttpPost]
    [RequireModulePermission("Feedback", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<FeedbackDto>>> Create([FromBody] FeedbackCreateDto dto)
    {
        var storeId = RequiredStoreId;
        var employeeId = await ResolveEmployeeIdAsync();

        var feedback = new Feedback
        {
            Id = Guid.NewGuid(),
            // Luôn lưu SenderEmployeeId để hiển thị trong "Của tôi", IsAnonymous quyết định ẩn/hiện
            SenderEmployeeId = employeeId,
            IsAnonymous = dto.IsAnonymous,
            RecipientEmployeeId = dto.RecipientEmployeeId,
            Title = dto.Title,
            Content = dto.Content,
            Category = dto.Category,
            Status = "Pending",
            StoreId = storeId,
            IsActive = true,
            CreatedBy = CurrentUserId.ToString(),
        };

        dbContext.Feedbacks.Add(feedback);
        await dbContext.SaveChangesAsync();

        try
        {
            var senderLabel = dto.IsAnonymous
                ? "Ẩn danh"
                : (await ResolveDisplayNameAsync(employeeId, CurrentUserId.ToString()) ?? "Nhân viên");

            if (dto.RecipientEmployeeId.HasValue)
            {
                var recipientUserId =
                    await ResolveUserIdForEmployeeAsync(dto.RecipientEmployeeId);
                if (recipientUserId.HasValue && recipientUserId.Value != CurrentUserId)
                {
                    await notificationService.CreateAndSendAsync(
                        recipientUserId.Value, NotificationType.Info,
                        "Phản ánh mới",
                        $"Phản ánh từ {senderLabel}: \"{dto.Title}\"",
                        relatedEntityType: "Feedback", relatedEntityId: feedback.Id,
                        fromUserId: CurrentUserId, categoryCode: "feedback", storeId: storeId);
                }
            }
            else
            {
                await NotifyFeedbackApproversNewItemAsync(feedback, senderLabel);
            }
        }
        catch { /* Notification failure should not affect main operation */ }

        string? recipientName = null;
        if (dto.RecipientEmployeeId.HasValue)
        {
            recipientName = await GetEmployeeNameAsync(dto.RecipientEmployeeId);
        }

        return Ok(AppResponse<FeedbackDto>.Success(new FeedbackDto(
            feedback.Id, feedback.Title, feedback.Content, feedback.Category, feedback.Status,
            feedback.IsAnonymous, null, null, feedback.SenderEmployeeId,
            feedback.RecipientEmployeeId, recipientName,
            null, null, null, feedback.CreatedAt)));
    }

    // ══════════════════ RESPOND (Manager/Admin) ══════════════════

    [HttpPut("{id}/respond")]
    [RequireModulePermission("Feedback", ModulePermissionAction.Approve)]
    public async Task<ActionResult<AppResponse<bool>>> Respond(Guid id, [FromBody] FeedbackRespondDto dto)
    {
        var storeId = RequiredStoreId;
        var employeeId = await ResolveEmployeeIdAsync();

        var feedback = await dbContext.Feedbacks.AsTracking()
            .FirstOrDefaultAsync(f => f.Id == id && f.StoreId == storeId && f.Deleted == null);
        if (feedback == null)
            return NotFound(AppResponse<bool>.Fail("Không tìm thấy phản ánh"));

        feedback.Response = dto.Response;
        feedback.Status = dto.Status;
        feedback.RespondedByEmployeeId = employeeId;
        feedback.RespondedAt = DateTime.Now;
        feedback.UpdatedAt = DateTime.Now;
        feedback.UpdatedBy = CurrentUserId.ToString();

        await dbContext.SaveChangesAsync();

        // Notify the feedback sender about the response
        try
        {
            var senderUserId = await ResolveUserIdForEmployeeAsync(
                feedback.SenderEmployeeId, feedback.CreatedBy);
            if (senderUserId.HasValue && senderUserId.Value != CurrentUserId)
            {
                var statusLabel = dto.Status switch
                {
                    "Resolved" => "đã giải quyết",
                    "Closed" => "đã đóng",
                    "InProgress" => "đang xử lý",
                    _ => "đã được phản hồi"
                };
                await notificationService.CreateAndSendAsync(
                    senderUserId.Value, NotificationType.Info,
                    "Phản ánh được phản hồi",
                    $"Phản ánh \"{feedback.Title}\" {statusLabel}",
                    relatedEntityType: "Feedback", relatedEntityId: feedback.Id,
                    fromUserId: CurrentUserId, categoryCode: "feedback", storeId: storeId);
            }
        }
        catch { /* Notification failure should not affect main operation */ }

        return Ok(AppResponse<bool>.Success(true));
    }

    [HttpPatch("{id}/status")]
    [RequireModulePermission("Feedback", ModulePermissionAction.Approve)]
    public async Task<ActionResult<AppResponse<bool>>> UpdateStatus(
        Guid id, [FromBody] FeedbackStatusDto dto)
    {
        var storeId = RequiredStoreId;
        var feedback = await dbContext.Feedbacks.AsTracking()
            .FirstOrDefaultAsync(f => f.Id == id && f.StoreId == storeId && f.Deleted == null);
        if (feedback == null)
            return NotFound(AppResponse<bool>.Fail("Không tìm thấy phản ánh"));

        var allowed = new[] { "Pending", "InProgress", "Resolved", "Closed" };
        if (!allowed.Contains(dto.Status))
            return BadRequest(AppResponse<bool>.Fail("Trạng thái không hợp lệ"));

        feedback.Status = dto.Status;
        feedback.UpdatedAt = DateTime.Now;
        feedback.UpdatedBy = CurrentUserId.ToString();
        if (dto.Status is "Resolved" or "Closed")
        {
            feedback.RespondedAt ??= DateTime.Now;
            feedback.RespondedByEmployeeId ??= await ResolveEmployeeIdAsync();
        }

        await dbContext.SaveChangesAsync();

        try
        {
            var senderUserId = await ResolveUserIdForEmployeeAsync(
                feedback.SenderEmployeeId, feedback.CreatedBy);
            if (senderUserId.HasValue && senderUserId.Value != CurrentUserId)
            {
                var statusLabel = dto.Status switch
                {
                    "Resolved" => "đã giải quyết",
                    "Closed" => "đã đóng",
                    "InProgress" => "đang xử lý",
                    "Pending" => "chờ xử lý",
                    _ => "đã cập nhật"
                };
                await notificationService.CreateAndSendAsync(
                    senderUserId.Value, NotificationType.Info,
                    "Cập nhật phản ánh",
                    $"Phản ánh \"{feedback.Title}\" {statusLabel}",
                    relatedEntityType: "Feedback", relatedEntityId: feedback.Id,
                    fromUserId: CurrentUserId, categoryCode: "feedback", storeId: storeId);
            }
        }
        catch { /* Notification failure should not affect main operation */ }

        return Ok(AppResponse<bool>.Success(true));
    }

    // ══════════════════ DELETE ══════════════════

    [HttpDelete("{id}")]
    [RequireModulePermission("Feedback", ModulePermissionAction.Delete)]
    public async Task<ActionResult<AppResponse<bool>>> Delete(Guid id)
    {
        var storeId = RequiredStoreId;
        var employeeId = await ResolveEmployeeIdAsync();

        var feedback = await dbContext.Feedbacks.AsTracking()
            .FirstOrDefaultAsync(f => f.Id == id && f.StoreId == storeId && f.Deleted == null);
        if (feedback == null)
            return NotFound(AppResponse<bool>.Fail("Không tìm thấy phản ánh"));

        // Chỉ người gửi hoặc admin mới được xóa
        if (!IsAdmin && feedback.SenderEmployeeId != employeeId && feedback.CreatedBy != CurrentUserId.ToString())
            return BadRequest(AppResponse<bool>.Fail("Bạn không có quyền xóa phản ánh này"));

        feedback.Deleted = DateTime.Now;
        feedback.DeletedBy = CurrentUserId.ToString();
        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<bool>.Success(true));
    }

    // ══════════════════ GET MANAGERS (for dropdown) ══════════════════

    [HttpGet("managers")]
    [RequireModulePermission("Feedback", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<object>>>> GetManagers()
    {
        var storeId = RequiredStoreId;

        var managers = await dbContext.Employees
            .Where(e => e.StoreId == storeId && e.Deleted == null
                && e.ApplicationUser != null)
            .OrderBy(e => e.LastName).ThenBy(e => e.FirstName)
            .Select(e => new
            {
                e.Id,
                Name = (e.LastName + " " + e.FirstName).Trim(),
                e.EmployeeCode,
                e.Position,
            })
            .ToListAsync();

        return Ok(AppResponse<List<object>>.Success(managers.Cast<object>().ToList()));
    }

    // ══════════════════ UPLOAD IMAGE ══════════════════

    [HttpPost("upload-image")]
    [RequireModulePermission("Feedback", ModulePermissionAction.Create)]
    [RequestSizeLimit(10_000_000)]
    public async Task<ActionResult<AppResponse<object>>> UploadImage(IFormFile file)
    {
        if (file == null || file.Length == 0)
            return BadRequest(AppResponse<object>.Fail("Chưa chọn file"));

        var ext = Path.GetExtension(file.FileName).ToLowerInvariant();
        var allowedExts = new[] { ".jpg", ".jpeg", ".png", ".gif", ".webp" };
        if (!allowedExts.Contains(ext))
            return BadRequest(AppResponse<object>.Fail("Chỉ hỗ trợ ảnh JPG, PNG, GIF, WEBP"));

        try
        {
            var storeFolder = await GetStoreFolderAsync("uploads/feedback");
            await using var raw = file.OpenReadStream();
            var (optimized, uploadName, _) = await ImageOptimizeHelper.OptimizeAsync(
                raw,
                file.FileName,
                ImageOptimizeHelper.PhotoMaxEdge,
                ImageOptimizeHelper.PhotoJpegQuality);
            await using (optimized)
            {
                var filePath = await fileStorageService.UploadAsync(optimized, uploadName, storeFolder);
                var fileUrl = fileStorageService.GetFileUrl(filePath);
                return Ok(AppResponse<object>.Success(new { filePath, fileUrl }));
            }
        }
        catch
        {
            return StatusCode(500, AppResponse<object>.Fail("Không thể tải ảnh lên"));
        }
    }

    // ══════════════════ REPLIES (Chat-style) ══════════════════

    [HttpGet("{id}/replies")]
    [RequireModulePermission("Feedback", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> GetReplies(Guid id)
    {
        var storeId = RequiredStoreId;
        var employeeId = await ResolveEmployeeIdAsync();

        var feedback = await dbContext.Feedbacks
            .FirstOrDefaultAsync(f => f.Id == id && f.StoreId == storeId && f.Deleted == null);
        if (feedback == null)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy phản ánh"));

        if (!await CanAccessFeedbackAsync(feedback, employeeId))
            return BadRequest(AppResponse<object>.Fail("Không có quyền xem"));

        var replies = await dbContext.FeedbackReplies
            .Where(r => r.FeedbackId == id)
            .OrderBy(r => r.CreatedAt)
            .Select(r => new
            {
                r.Id, r.FeedbackId, r.Content, r.ImageUrls,
                r.IsFromSender, r.SenderEmployeeId, r.CreatedAt, r.CreatedBy,
                SenderName = r.SenderEmployee != null
                    ? (r.SenderEmployee.LastName + " " + r.SenderEmployee.FirstName).Trim() : null,
            })
            .ToListAsync();

        var needUserResolve = replies
            .Where(r => string.IsNullOrWhiteSpace(r.SenderName)
                && !string.IsNullOrEmpty(r.CreatedBy))
            .Select(r => r.CreatedBy!)
            .Distinct()
            .ToList();
        var userNames = needUserResolve.Count > 0
            ? await dbContext.Users
                .Where(u => needUserResolve.Contains(u.Id.ToString()))
                .ToDictionaryAsync(
                    u => u.Id.ToString(),
                    u => ((u.LastName ?? "") + " " + (u.FirstName ?? "")).Trim())
            : new Dictionary<string, string>();

        var result = replies.Select(r =>
        {
            var hideSender = feedback.IsAnonymous && r.IsFromSender;
            var senderName = hideSender
                ? null
                : (r.SenderName
                    ?? (r.CreatedBy != null && userNames.TryGetValue(r.CreatedBy, out var un)
                        ? un : null));
            return new FeedbackReplyDto(
                r.Id, r.FeedbackId, r.Content, ParseImageUrls(r.ImageUrls),
                r.IsFromSender,
                senderName,
                hideSender ? null : r.SenderEmployeeId,
                r.CreatedAt,
                IsReplyFromCurrentUser(
                    r.SenderEmployeeId, r.CreatedBy, employeeId, CurrentUserId));
        }).ToList();

        var senderName = feedback.IsAnonymous
            ? null
            : await ResolveDisplayNameAsync(feedback.SenderEmployeeId, feedback.CreatedBy);
        var recipientName = await GetEmployeeNameAsync(feedback.RecipientEmployeeId);
        var canReply = await CanReplyToFeedbackAsync(feedback, employeeId);

        return Ok(AppResponse<object>.Success(new
        {
            feedback = new
            {
                feedback.Id, feedback.Title, feedback.Content, feedback.Category,
                feedback.Status, feedback.IsAnonymous,
                SenderName = senderName,
                feedback.SenderEmployeeId,
                RecipientName = recipientName,
                feedback.RecipientEmployeeId,
                ImageUrls = ParseImageUrls(feedback.ImageUrls),
                feedback.CreatedAt,
            },
            replies = result,
            viewerContext = new
            {
                canReply,
                isOriginalSender = IsOriginalFeedbackSender(feedback, employeeId),
                employeeId,
            },
        }));
    }

    [HttpPost("{id}/replies")]
    [RequireModulePermission("Feedback", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<FeedbackReplyDto>>> CreateReply(
        Guid id, [FromBody] FeedbackReplyCreateDto dto)
    {
        var storeId = RequiredStoreId;
        var employeeId = await ResolveEmployeeIdAsync();

        var feedback = await dbContext.Feedbacks.AsTracking()
            .FirstOrDefaultAsync(f => f.Id == id && f.StoreId == storeId && f.Deleted == null);
        if (feedback == null)
            return NotFound(AppResponse<FeedbackReplyDto>.Fail("Không tìm thấy phản ánh"));

        if (!await CanReplyToFeedbackAsync(feedback, employeeId))
            return BadRequest(AppResponse<FeedbackReplyDto>.Fail("Không có quyền phản hồi"));

        var isSender = IsOriginalFeedbackSender(feedback, employeeId);

        var reply = new FeedbackReply
        {
            Id = Guid.NewGuid(),
            FeedbackId = id,
            SenderEmployeeId = employeeId,
            Content = dto.Content,
            IsFromSender = isSender,
            StoreId = storeId,
            CreatedBy = CurrentUserId.ToString(),
        };

        dbContext.FeedbackReplies.Add(reply);

        // Auto-update feedback status if it's still Pending
        if (feedback.Status == "Pending" && !isSender)
        {
            feedback.Status = "InProgress";
        }
        feedback.UpdatedAt = DateTime.Now;
        feedback.UpdatedBy = CurrentUserId.ToString();

        await dbContext.SaveChangesAsync();

        try
        {
            string senderLabel;
            if (isSender && feedback.IsAnonymous)
                senderLabel = "Ẩn danh";
            else
                senderLabel = await ResolveDisplayNameAsync(employeeId, CurrentUserId.ToString())
                    ?? "Nhân viên";

            var preview = dto.Content.Length > 100 ? dto.Content[..100] + "..." : dto.Content;
            await NotifyFeedbackReplyAsync(feedback, senderLabel, preview, isSender);
        }
        catch { /* Notification failure should not affect main operation */ }

        var senderName = await ResolveDisplayNameAsync(employeeId, CurrentUserId.ToString());

        return Ok(AppResponse<FeedbackReplyDto>.Success(new FeedbackReplyDto(
            reply.Id, reply.FeedbackId, reply.Content, null,
            reply.IsFromSender,
            feedback.IsAnonymous && isSender ? null : senderName,
            feedback.IsAnonymous && isSender ? null : employeeId,
            reply.CreatedAt,
            true
        )));
    }

    // ══════════════════ UPLOAD REPLY IMAGE ══════════════════

    [HttpPost("{id}/replies/{replyId}/image")]
    [RequestSizeLimit(10_000_000)]
    public async Task<ActionResult<AppResponse<object>>> UploadReplyImage(
        Guid id, Guid replyId, IFormFile file)
    {
        if (file == null || file.Length == 0)
            return BadRequest(AppResponse<object>.Fail("Chưa chọn file"));

        var reply = await dbContext.FeedbackReplies.AsTracking()
            .FirstOrDefaultAsync(r => r.Id == replyId && r.FeedbackId == id);
        if (reply == null)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy phản hồi"));

        // Only the reply creator can add images
        if (reply.CreatedBy != CurrentUserId.ToString())
            return BadRequest(AppResponse<object>.Fail("Không có quyền"));

        var ext = Path.GetExtension(file.FileName).ToLowerInvariant();
        var allowedExts = new[] { ".jpg", ".jpeg", ".png", ".gif", ".webp" };
        if (!allowedExts.Contains(ext))
            return BadRequest(AppResponse<object>.Fail("Chỉ hỗ trợ ảnh JPG, PNG, GIF, WEBP"));

        try
        {
            var storeFolder = await GetStoreFolderAsync("uploads/feedback");
            using var stream = file.OpenReadStream();
            var filePath = await fileStorageService.UploadAsync(stream, file.FileName, storeFolder);
            var fileUrl = fileStorageService.GetFileUrl(filePath);

            // Append to reply's ImageUrls
            var urls = ParseImageUrls(reply.ImageUrls) ?? new List<string>();
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

    // ══════════════════ HELPERS ══════════════════

    private async Task<string> GetStoreFolderAsync(string subfolder)
    {
        var storeId = CurrentStoreId;
        if (storeId.HasValue)
        {
            var storeCode = await dbContext.Stores
                .Where(s => s.Id == storeId.Value)
                .Select(s => s.Code)
                .FirstOrDefaultAsync();
            if (!string.IsNullOrEmpty(storeCode))
                return $"stores/{storeCode}/{subfolder}";
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

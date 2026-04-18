using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using System.Text.Json;
using ZKTecoADMS.Api.Controllers.Base;
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

    public record FeedbackReplyDto(
        Guid Id, Guid FeedbackId, string Content, List<string>? ImageUrls,
        bool IsFromSender, string? SenderName, Guid? SenderEmployeeId,
        DateTime CreatedAt);

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

    // ══════════════════ GET ALL (Manager/Admin) ══════════════════

    [HttpGet]
    public async Task<ActionResult<AppResponse<object>>> GetAll(
        [FromQuery] string? status, [FromQuery] string? category,
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
            query = query.Where(f => f.RecipientEmployeeId == null);
        }

        if (!string.IsNullOrEmpty(status))
            query = query.Where(f => f.Status == status);
        if (!string.IsNullOrEmpty(category))
            query = query.Where(f => f.Category == category);

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
    public async Task<ActionResult<AppResponse<List<FeedbackDto>>>> GetMyFeedbacks()
    {
        var storeId = RequiredStoreId;
        var employeeId = await ResolveEmployeeIdAsync();
        var userId = CurrentUserId.ToString();

        var rawItems = await dbContext.Feedbacks
            .Where(f => f.StoreId == storeId && f.Deleted == null
                && (f.SenderEmployeeId == employeeId || f.CreatedBy == userId))
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
    public async Task<ActionResult<AppResponse<FeedbackDto>>> Create([FromBody] FeedbackCreateDto dto)
    {
        var storeId = RequiredStoreId;
        var employeeId = await ResolveEmployeeIdAsync();

        var feedback = new Feedback
        {
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

        // Notify recipient manager about new feedback
        try
        {
            if (dto.RecipientEmployeeId.HasValue)
            {
                var recipientUserId = await dbContext.Employees
                    .Where(e => e.Id == dto.RecipientEmployeeId.Value && e.ApplicationUserId != null)
                    .Select(e => e.ApplicationUserId!.Value)
                    .FirstOrDefaultAsync();
                if (recipientUserId != Guid.Empty && recipientUserId != CurrentUserId)
                {
                    var senderLabel = dto.IsAnonymous ? "Ẩn danh" : (await GetEmployeeNameAsync(employeeId) ?? "Nhân viên");
                    await notificationService.CreateAndSendAsync(
                        recipientUserId, NotificationType.Info,
                        "Phản ánh mới",
                        $"Phản ánh từ {senderLabel}: \"{dto.Title}\"",
                        relatedEntityType: "Feedback", relatedEntityId: feedback.Id,
                        fromUserId: CurrentUserId, categoryCode: "feedback", storeId: storeId);
                }
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
            if (feedback.SenderEmployeeId.HasValue)
            {
                var senderUserId = await dbContext.Employees
                    .Where(e => e.Id == feedback.SenderEmployeeId.Value && e.ApplicationUserId != null)
                    .Select(e => e.ApplicationUserId!.Value)
                    .FirstOrDefaultAsync();
                if (senderUserId != Guid.Empty && senderUserId != CurrentUserId)
                {
                    var statusLabel = dto.Status switch
                    {
                        "Resolved" => "đã giải quyết",
                        "Closed" => "đã đóng",
                        "InProgress" => "đang xử lý",
                        _ => "đã được phản hồi"
                    };
                    await notificationService.CreateAndSendAsync(
                        senderUserId, NotificationType.Info,
                        "Phản ánh được phản hồi",
                        $"Phản ánh \"{feedback.Title}\" {statusLabel}",
                        relatedEntityType: "Feedback", relatedEntityId: feedback.Id,
                        fromUserId: CurrentUserId, categoryCode: "feedback", storeId: storeId);
                }
            }
        }
        catch { /* Notification failure should not affect main operation */ }

        return Ok(AppResponse<bool>.Success(true));
    }

    // ══════════════════ DELETE ══════════════════

    [HttpDelete("{id}")]
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
            using var stream = file.OpenReadStream();
            var filePath = await fileStorageService.UploadAsync(stream, file.FileName, storeFolder);
            var fileUrl = fileStorageService.GetFileUrl(filePath);

            return Ok(AppResponse<object>.Success(new { filePath, fileUrl }));
        }
        catch
        {
            return StatusCode(500, AppResponse<object>.Fail("Không thể tải ảnh lên"));
        }
    }

    // ══════════════════ REPLIES (Chat-style) ══════════════════

    [HttpGet("{id}/replies")]
    public async Task<ActionResult<AppResponse<object>>> GetReplies(Guid id)
    {
        var storeId = RequiredStoreId;
        var employeeId = await ResolveEmployeeIdAsync();

        var feedback = await dbContext.Feedbacks
            .FirstOrDefaultAsync(f => f.Id == id && f.StoreId == storeId && f.Deleted == null);
        if (feedback == null)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy phản ánh"));

        // Check access
        if (!IsAdmin && !IsManager
            && feedback.SenderEmployeeId != employeeId
            && feedback.CreatedBy != CurrentUserId.ToString())
            return BadRequest(AppResponse<object>.Fail("Không có quyền xem"));

        var replies = await dbContext.FeedbackReplies
            .Where(r => r.FeedbackId == id)
            .OrderBy(r => r.CreatedAt)
            .Select(r => new
            {
                r.Id, r.FeedbackId, r.Content, r.ImageUrls,
                r.IsFromSender, r.SenderEmployeeId, r.CreatedAt,
                SenderName = r.SenderEmployee != null
                    ? (r.SenderEmployee.LastName + " " + r.SenderEmployee.FirstName).Trim() : null,
            })
            .ToListAsync();

        // For anonymous feedback, hide sender name when IsFromSender=true
        var result = replies.Select(r => new FeedbackReplyDto(
            r.Id, r.FeedbackId, r.Content, ParseImageUrls(r.ImageUrls),
            r.IsFromSender,
            feedback.IsAnonymous && r.IsFromSender ? null : r.SenderName,
            feedback.IsAnonymous && r.IsFromSender ? null : r.SenderEmployeeId,
            r.CreatedAt
        )).ToList();

        // Also return feedback info for chat header
        var senderName = feedback.IsAnonymous ? null : await GetEmployeeNameAsync(feedback.SenderEmployeeId);
        var recipientName = await GetEmployeeNameAsync(feedback.RecipientEmployeeId);

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
        }));
    }

    [HttpPost("{id}/replies")]
    public async Task<ActionResult<AppResponse<FeedbackReplyDto>>> CreateReply(
        Guid id, [FromBody] FeedbackReplyCreateDto dto)
    {
        var storeId = RequiredStoreId;
        var employeeId = await ResolveEmployeeIdAsync();

        var feedback = await dbContext.Feedbacks.AsTracking()
            .FirstOrDefaultAsync(f => f.Id == id && f.StoreId == storeId && f.Deleted == null);
        if (feedback == null)
            return NotFound(AppResponse<FeedbackReplyDto>.Fail("Không tìm thấy phản ánh"));

        // Determine if the reply is from the original sender
        var isSender = feedback.SenderEmployeeId == employeeId
            || feedback.CreatedBy == CurrentUserId.ToString();

        // Check access: sender or recipient/admin/manager
        if (!isSender && !IsAdmin && !IsManager
            && feedback.RecipientEmployeeId != employeeId)
            return BadRequest(AppResponse<FeedbackReplyDto>.Fail("Không có quyền phản hồi"));

        var reply = new FeedbackReply
        {
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

        // Send notification to the other party
        try
        {
            Guid? targetEmployeeId = isSender
                ? feedback.RecipientEmployeeId  // sender replied → notify recipient
                : feedback.SenderEmployeeId;    // recipient replied → notify sender

            if (targetEmployeeId.HasValue)
            {
                var targetUserId = await dbContext.Employees
                    .Where(e => e.Id == targetEmployeeId.Value && e.ApplicationUserId != null)
                    .Select(e => e.ApplicationUserId!.Value)
                    .FirstOrDefaultAsync();

                if (targetUserId != Guid.Empty && targetUserId != CurrentUserId)
                {
                    string senderLabel;
                    if (isSender && feedback.IsAnonymous)
                        senderLabel = "Ẩn danh";
                    else
                        senderLabel = await GetEmployeeNameAsync(employeeId) ?? "Nhân viên";

                    var preview = dto.Content.Length > 100 ? dto.Content[..100] + "..." : dto.Content;
                    await notificationService.CreateAndSendAsync(
                        targetUserId, NotificationType.Info,
                        "Phản hồi mới",
                        $"{senderLabel}: \"{preview}\"",
                        relatedEntityType: "Feedback", relatedEntityId: feedback.Id,
                        fromUserId: CurrentUserId, categoryCode: "feedback", storeId: storeId);
                }
            }
        }
        catch { /* Notification failure should not affect main operation */ }

        var senderName = await GetEmployeeNameAsync(employeeId);

        return Ok(AppResponse<FeedbackReplyDto>.Success(new FeedbackReplyDto(
            reply.Id, reply.FeedbackId, reply.Content, null,
            reply.IsFromSender,
            feedback.IsAnonymous && isSender ? null : senderName,
            feedback.IsAnonymous && isSender ? null : employeeId,
            reply.CreatedAt
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

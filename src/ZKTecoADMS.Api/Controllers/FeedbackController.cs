using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
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
public class FeedbackController(ZKTecoDbContext dbContext, ISystemNotificationService notificationService) : AuthenticatedControllerBase
{
    #region DTOs

    public record FeedbackDto(
        Guid Id, string Title, string Content, string Category, string Status,
        bool IsAnonymous, string? SenderName, string? SenderCode,
        Guid? SenderEmployeeId, Guid? RecipientEmployeeId,
        string? RecipientName, string? Response,
        string? RespondedByName, DateTime? RespondedAt,
        DateTime CreatedAt);

    public record FeedbackCreateDto(
        string Title, string Content, string Category,
        bool IsAnonymous, Guid? RecipientEmployeeId);

    public record FeedbackRespondDto(string Response, string Status);

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
            f.CreatedAt
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
                RecipientName = f.RecipientEmployee != null
                    ? (f.RecipientEmployee.LastName + " " + f.RecipientEmployee.FirstName).Trim() : null,
                f.Response,
                RespondedByName = f.RespondedByEmployee != null
                    ? (f.RespondedByEmployee.LastName + " " + f.RespondedByEmployee.FirstName).Trim() : null,
                f.RespondedByEmployeeId,
                f.RespondedAt, f.CreatedAt,
                f.UpdatedBy,
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
            f.RespondedAt, f.CreatedAt
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
}

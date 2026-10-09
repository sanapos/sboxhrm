using ZKTecoADMS.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Api.Hubs;
using ZKTecoADMS.Application.Commands.Notifications;
using ZKTecoADMS.Application.Queries.Notifications;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.DTOs.Notifications;
using ZKTecoADMS.Application.DTOs.Commons;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Application.Notifications;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Helpers;
using ZKTecoADMS.Infrastructure.Services.Push;

namespace ZKTecoADMS.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
public class NotificationsController(
    IMediator mediator,
    ZKTecoDbContext db,
    IHubContext<AttendanceHub> hubContext,
    IPushNotificationService push,
    ILogger<NotificationsController> logger) : AuthenticatedControllerBase
{
    private readonly ILogger<NotificationsController> _logger = logger;
    [HttpGet]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("Notification", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<PagedResult<NotificationDto>>>> GetUserNotifications(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20,
        [FromQuery] bool? isRead = null,
        [FromQuery] NotificationType? type = null,
        [FromQuery] string? category = null,
        [FromQuery] string? q = null)
    {
        // category: danh sách mã loại, phân tách dấu phẩy (VD "attendance,shift"); "none" = thông báo cũ chưa gắn loại.
        var cats = string.IsNullOrWhiteSpace(category)
            ? null
            : category.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
                .Select(c => c.ToLowerInvariant()).Distinct().ToList();
        var query = new GetUserNotificationsQuery(
            CurrentUserId, CurrentStoreId, NotificationCrossStore, page, pageSize, isRead, type,
            cats, string.IsNullOrWhiteSpace(q) ? null : q.Trim()[..Math.Min(q.Trim().Length, 100)]);
        var result = await mediator.Send(query);
        return Ok(result);
    }

    [HttpGet("summary")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("Notification", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<NotificationSummaryDto>>> GetNotificationSummary()
    {
        var query = new GetNotificationSummaryQuery(CurrentUserId, CurrentStoreId, NotificationCrossStore);
        var result = await mediator.Send(query);
        return Ok(result);
    }

    [HttpGet("unread-count")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("Notification", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<int>>> GetUnreadCount()
    {
        var query = new GetUnreadCountQuery(CurrentUserId, CurrentStoreId, NotificationCrossStore);
        var result = await mediator.Send(query);
        return Ok(result);
    }

    [HttpGet("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("Notification", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<NotificationDto>>> GetNotificationById(Guid id)
    {
        var query = new GetNotificationByIdQuery(id, CurrentUserId, CurrentStoreId, NotificationCrossStore);
        var result = await mediator.Send(query);
        return Ok(result);
    }

    [HttpPost]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("Notification", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<NotificationDto>>> CreateNotification([FromBody] CreateNotificationDto request)
    {
        var command = new CreateNotificationCommand(
            RequiredStoreId,
            request.TargetUserId,
            request.Type,
            request.Title,
            request.Message,
            request.RelatedUrl,
            request.RelatedEntityId,
            request.RelatedEntityType,
            CurrentUserId);
        
        var result = await mediator.Send(command);
        return Ok(result);
    }

    [HttpPost("bulk")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("Notification", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<List<NotificationDto>>>> BulkCreateNotifications([FromBody] BulkCreateNotificationDto request)
    {
        var command = new BulkCreateNotificationsCommand(
            RequiredStoreId,
            request.TargetUserIds,
            request.Type,
            request.Title,
            request.Message,
            request.RelatedUrl,
            CurrentUserId);
        
        var result = await mediator.Send(command);
        return Ok(result);
    }

    [HttpPost("{id}/read")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("Notification", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<NotificationDto>>> MarkNotificationAsRead(Guid id)
    {
        var command = new MarkNotificationReadCommand(id, CurrentUserId, CurrentStoreId, NotificationCrossStore);
        var result = await mediator.Send(command);
        if (result.IsSuccess)
        {
            // Notify other devices/tabs of this user so they can update the badge and
            // greyed-out state immediately, instead of waiting for the next manual refresh.
            await BroadcastToUserAsync("NotificationRead", new { id = id.ToString(), all = false });
            await SyncBadgeSafeAsync();
        }
        return Ok(result);
    }

    /// <summary>Đánh dấu lại là chưa đọc (để xử lý sau).</summary>
    [HttpPost("{id}/unread")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("Notification", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<bool>>> MarkNotificationAsUnread(Guid id)
    {
        var filter = NotificationUserScope.FilterById(id, CurrentUserId, CurrentStoreId, NotificationCrossStore);
        var n = await db.Notifications.Where(filter).FirstOrDefaultAsync();
        if (n == null) return Ok(AppResponse<bool>.Fail("Không tìm thấy thông báo"));
        if (n.IsRead)
        {
            n.IsRead = false;
            n.ReadAt = null;
            n.UpdatedAt = DateTime.UtcNow;
            await db.SaveChangesAsync();
        }
        await BroadcastToUserAsync("NotificationUnread", new { id = id.ToString() });
        await SyncBadgeSafeAsync();
        return Ok(AppResponse<bool>.Success(true));
    }

    /// <summary>Đánh dấu đã đọc cả 1 nhóm loại (VD tất cả thông báo chấm công).</summary>
    [HttpPost("read-category")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("Notification", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<int>>> MarkCategoryAsRead([FromQuery] string category)
    {
        var cats = (category ?? "").Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Select(c => c.ToLowerInvariant()).Distinct().ToList();
        if (cats.Count == 0) return Ok(AppResponse<int>.Fail("Thiếu loại thông báo"));
        var filter = NotificationUserScope.FilterForUser(CurrentUserId, CurrentStoreId, NotificationCrossStore,
            isRead: false, categories: cats);
        var now = DateTime.UtcNow;
        var count = await db.Notifications.Where(filter).ExecuteUpdateAsync(s => s
            .SetProperty(n => n.IsRead, true)
            .SetProperty(n => n.ReadAt, now)
            .SetProperty(n => n.UpdatedAt, now));
        await BroadcastToUserAsync("NotificationRead", new { id = (string?)null, all = false, category = string.Join(',', cats) });
        await SyncBadgeSafeAsync();
        return Ok(AppResponse<int>.Success(count));
    }

    /// <summary>Số thông báo (tổng / chưa đọc) theo từng loại — cho thanh lọc có số đếm.</summary>
    [HttpGet("category-counts")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("Notification", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<NotificationCategoryCountDto>>>> GetCategoryCounts()
    {
        var filter = NotificationUserScope.FilterForUser(CurrentUserId, CurrentStoreId, NotificationCrossStore);
        var rows = await db.Notifications.AsNoTracking().Where(filter)
            .GroupBy(n => n.CategoryCode)
            .Select(g => new { Code = g.Key, Total = g.Count(), Unread = g.Count(x => !x.IsRead) })
            .ToListAsync();
        var list = rows
            .Select(r => new NotificationCategoryCountDto(r.Code ?? NotificationUserScope.UncategorizedCode, r.Total, r.Unread))
            .OrderByDescending(r => r.Unread).ThenByDescending(r => r.Total)
            .ToList();
        return Ok(AppResponse<List<NotificationCategoryCountDto>>.Success(list));
    }

    public record NotificationCategoryCountDto(string Code, int Total, int Unread);

    private async Task SyncBadgeSafeAsync()
    {
        try
        {
            await push.SyncBadgeAsync(CurrentUserId);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Sync FCM badge failed for {UserId}", CurrentUserId);
        }
    }

    [HttpPost("read-all")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("Notification", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<int>>> MarkAllNotificationsAsRead()
    {
        var now = DateTime.UtcNow;
        var userId = CurrentUserId;
        var storeId = CurrentStoreId;
        var crossStore = NotificationCrossStore;
        var unread = db.Notifications.Where(n => n.TargetUserId == userId && !n.IsRead);
        if (!crossStore)
            unread = unread.Where(n => n.StoreId == storeId || n.StoreId == null);

        var count = await unread.ExecuteUpdateAsync(s => s
            .SetProperty(n => n.IsRead, true)
            .SetProperty(n => n.ReadAt, now)
            .SetProperty(n => n.UpdatedAt, now));

        await BroadcastToUserAsync("NotificationRead", new { id = (string?)null, all = true });
        try
        {
            await push.ClearBadgeAsync(userId);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Clear FCM badge failed for {UserId}", userId);
        }

        return Ok(AppResponse<int>.Success(count));
    }

    [HttpDelete("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("Notification", ModulePermissionAction.Delete)]
    public async Task<ActionResult<AppResponse<bool>>> DeleteNotification(Guid id)
    {
        var command = new DeleteNotificationCommand(id, CurrentUserId, CurrentStoreId, NotificationCrossStore);
        var result = await mediator.Send(command);
        if (result.IsSuccess)
        {
            await BroadcastToUserAsync("NotificationDeleted", new { id = id.ToString(), all = false });
        }
        return Ok(result);
    }

    [HttpDelete]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("Notification", ModulePermissionAction.Delete)]
    public async Task<ActionResult<AppResponse<int>>> DeleteAllNotifications([FromQuery] bool? isRead = null)
    {
        var command = new DeleteAllNotificationsCommand(CurrentUserId, CurrentStoreId, NotificationCrossStore, isRead);
        var result = await mediator.Send(command);
        if (result.IsSuccess)
        {
            await BroadcastToUserAsync("NotificationDeleted", new { id = (string?)null, all = true, isRead });
        }
        return Ok(result);
    }

    /// <summary>Super Admin chỉ xem mọi cửa hàng khi token không gắn một cửa hàng.</summary>
    private bool NotificationCrossStore =>
        IsCrossStoreNotificationUser && !CurrentStoreId.HasValue;

    /// <summary>
    /// Push a sync event to every connection of the current user. Best-effort:
    /// SignalR failures are logged but don't fail the HTTP response (the DB row
    /// is already mutated and will surface on next manual reload).
    /// </summary>
    private async Task BroadcastToUserAsync(string eventName, object payload)
    {
        try
        {
            await hubContext.Clients.Group($"user_{CurrentUserId}").SendAsync(eventName, payload);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to broadcast {Event} to user {UserId}", eventName, CurrentUserId);
        }
    }

    // ---- FCM Device Token registration ----

    public class RegisterDeviceTokenRequest
    {
        public string Token { get; set; } = string.Empty;
        public string Platform { get; set; } = string.Empty;
        public string? DeviceName { get; set; }
        public string? AppVersion { get; set; }
        public string? DeviceKey { get; set; }
    }

    [HttpPost("device-token")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<bool>>> RegisterDeviceToken([FromBody] RegisterDeviceTokenRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.Token) || string.IsNullOrWhiteSpace(request.Platform))
        {
            return Ok(AppResponse<bool>.Error("Token and platform are required"));
        }

        var userId = CurrentUserId;
        if (CurrentStoreId is Guid sid)
        {
            var store = await db.Stores.AsNoTracking()
                .Include(s => s.ServicePackage)
                .FirstOrDefaultAsync(s => s.Id == sid);
            var allowFcm = store?.ServicePackage?.AllowFcm ?? store?.AllowFcm ?? true;
            if (!allowFcm)
                return Ok(AppResponse<bool>.Success(true));
        }

        var previousOwner = await DeviceTokenRegistry.RegisterAsync(db, userId, request.Token, request.Platform,
            request.DeviceName, request.AppVersion, request.DeviceKey);
        if (previousOwner is Guid old && old != userId)
            _logger.LogWarning("FCM token rebound: device token moved from user {OldUserId} to {NewUserId}", old, userId);
        return Ok(AppResponse<bool>.Success(true));
    }

    /// <summary>
    /// Gỡ token khi đăng xuất. Không cần đăng nhập: lúc phiên hết hạn app không còn access token hợp lệ,
    /// mà máy giữ đúng token FCM chính là máy đó — gỡ chỉ làm máy ngừng nhận thông báo.
    /// </summary>
    [HttpDelete("device-token")]
    [AllowAnonymous]
    public async Task<ActionResult<AppResponse<bool>>> UnregisterDeviceToken([FromQuery] string token)
    {
        if (string.IsNullOrWhiteSpace(token) || token.Length > 512)
        {
            return Ok(AppResponse<bool>.Error("Token is required"));
        }

        var removed = await db.UserDeviceTokens.Where(t => t.Token == token).ExecuteDeleteAsync();
        if (removed > 0) _logger.LogInformation("FCM token unregistered on logout ({Count})", removed);
        return Ok(AppResponse<bool>.Success(true));
    }

    [HttpPost("device-token/debug")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public ActionResult DebugDeviceToken([FromBody] DeviceTokenDebugRequest request)
    {
        var userId = CurrentUserId;
        _logger.LogWarning("[FCM DEBUG] UserId={UserId} Platform={Platform} Ts={Ts} Message={Message}",
            userId, request.Platform, request.Ts, request.Message);
        return Ok(new { ok = true });
    }
}

public record DeviceTokenDebugRequest(string Message, string Platform, string? Ts);


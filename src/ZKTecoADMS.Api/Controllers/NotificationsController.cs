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
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Helpers;

namespace ZKTecoADMS.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
public class NotificationsController(
    IMediator mediator,
    ZKTecoDbContext db,
    IHubContext<AttendanceHub> hubContext,
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
        [FromQuery] NotificationType? type = null)
    {
        var crossStore = IsCrossStoreNotificationUser;
        var storeId = CurrentStoreId;
        var query = new GetUserNotificationsQuery(CurrentUserId, storeId, crossStore, page, pageSize, isRead, type);
        var result = await mediator.Send(query);
        return Ok(result);
    }

    [HttpGet("summary")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("Notification", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<NotificationSummaryDto>>> GetNotificationSummary()
    {
        var crossStore = IsCrossStoreNotificationUser;
        var storeId = CurrentStoreId;
        var query = new GetNotificationSummaryQuery(CurrentUserId, storeId, crossStore);
        var result = await mediator.Send(query);
        return Ok(result);
    }

    [HttpGet("unread-count")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("Notification", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<int>>> GetUnreadCount()
    {
        var query = new GetUnreadCountQuery(CurrentUserId, CurrentStoreId, IsCrossStoreNotificationUser);
        var result = await mediator.Send(query);
        return Ok(result);
    }

    [HttpGet("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("Notification", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<NotificationDto>>> GetNotificationById(Guid id)
    {
        var query = new GetNotificationByIdQuery(id, CurrentUserId, CurrentStoreId, IsCrossStoreNotificationUser);
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
    [RequireModulePermission("Notification", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<NotificationDto>>> MarkNotificationAsRead(Guid id)
    {
        var command = new MarkNotificationReadCommand(id, CurrentUserId, CurrentStoreId, IsCrossStoreNotificationUser);
        var result = await mediator.Send(command);
        if (result.IsSuccess)
        {
            // Notify other devices/tabs of this user so they can update the badge and
            // greyed-out state immediately, instead of waiting for the next manual refresh.
            await BroadcastToUserAsync("NotificationRead", new { id = id.ToString(), all = false });
        }
        return Ok(result);
    }

    [HttpPost("read-all")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("Notification", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<int>>> MarkAllNotificationsAsRead()
    {
        var command = new MarkAllNotificationsReadCommand(CurrentUserId, CurrentStoreId, IsCrossStoreNotificationUser);
        var result = await mediator.Send(command);
        if (result.IsSuccess)
        {
            await BroadcastToUserAsync("NotificationRead", new { id = (string?)null, all = true });
        }
        return Ok(result);
    }

    [HttpDelete("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("Notification", ModulePermissionAction.Delete)]
    public async Task<ActionResult<AppResponse<bool>>> DeleteNotification(Guid id)
    {
        var command = new DeleteNotificationCommand(id, CurrentUserId, CurrentStoreId, IsCrossStoreNotificationUser);
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
        var command = new DeleteAllNotificationsCommand(CurrentUserId, CurrentStoreId, IsCrossStoreNotificationUser, isRead);
        var result = await mediator.Send(command);
        if (result.IsSuccess)
        {
            await BroadcastToUserAsync("NotificationDeleted", new { id = (string?)null, all = true, isRead });
        }
        return Ok(result);
    }

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

        var existing = await db.UserDeviceTokens
            .FirstOrDefaultAsync(t => t.Token == request.Token);

        if (existing != null)
        {
            if (existing.UserId != userId)
            {
                _logger.LogWarning(
                    "FCM token rebound: device token moved from user {OldUserId} to {NewUserId}",
                    existing.UserId, userId);
            }
            // Rebind to current user (same device, different login) and re-enable.
            existing.UserId = userId;
            existing.Platform = request.Platform;
            existing.DeviceName = request.DeviceName;
            existing.AppVersion = request.AppVersion;
            existing.IsDisabled = false;
            existing.LastUsedAt = null;
        }
        else
        {
            db.UserDeviceTokens.Add(new UserDeviceToken
            {
                Id = Guid.NewGuid(),
                UserId = userId,
                Token = request.Token,
                Platform = request.Platform,
                DeviceName = request.DeviceName,
                AppVersion = request.AppVersion,
                IsDisabled = false,
            });
        }

        // Gỡ app không gọi DELETE token — vô hiệu token cũ cùng user+platform, chỉ giữ token hiện tại.
        var stale = await db.UserDeviceTokens
            .Where(t => t.UserId == userId
                        && t.Platform == request.Platform
                        && t.Token != request.Token
                        && !t.IsDisabled)
            .ToListAsync();
        foreach (var t in stale)
            t.IsDisabled = true;

        await db.SaveChangesAsync();
        return Ok(AppResponse<bool>.Success(true));
    }

    [HttpDelete("device-token")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<bool>>> UnregisterDeviceToken([FromQuery] string token)
    {
        if (string.IsNullOrWhiteSpace(token))
        {
            return Ok(AppResponse<bool>.Error("Token is required"));
        }

        var userId = CurrentUserId;
        var existing = await db.UserDeviceTokens
            .FirstOrDefaultAsync(t => t.Token == token && t.UserId == userId);
        if (existing != null)
        {
            db.UserDeviceTokens.Remove(existing);
            await db.SaveChangesAsync();
        }
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


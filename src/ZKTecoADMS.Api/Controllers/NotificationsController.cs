using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.SignalR;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Api.Hubs;
using ZKTecoADMS.Application.Commands.Notifications;
using ZKTecoADMS.Application.Queries.Notifications;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.DTOs.Notifications;
using ZKTecoADMS.Application.DTOs.Commons;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure;
using Microsoft.EntityFrameworkCore;

namespace ZKTecoADMS.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
public class NotificationsController(
    IMediator mediator,
    IHubContext<AttendanceHub> hubContext,
    ZKTecoDbContext db) : AuthenticatedControllerBase
{
    public sealed class RegisterDeviceTokenRequest
    {
        public string Token { get; set; } = string.Empty;
        public string Platform { get; set; } = string.Empty;
        public string? DeviceName { get; set; }
        public string? AppVersion { get; set; }
    }

    /// <summary>Register / refresh an FCM token for the current user.</summary>
    [HttpPost("device-token")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<bool>>> RegisterDeviceToken([FromBody] RegisterDeviceTokenRequest request, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(request.Token) || string.IsNullOrWhiteSpace(request.Platform))
            return BadRequest(AppResponse<bool>.Fail("Token and Platform are required"));

        var existing = await db.UserDeviceTokens.FirstOrDefaultAsync(t => t.Token == request.Token, ct);
        if (existing == null)
        {
            db.UserDeviceTokens.Add(new UserDeviceToken
            {
                Id = Guid.NewGuid(),
                UserId = CurrentUserId,
                Token = request.Token.Trim(),
                Platform = request.Platform.Trim().ToLowerInvariant(),
                DeviceName = request.DeviceName,
                AppVersion = request.AppVersion,
                IsDisabled = false,
            });
        }
        else
        {
            // Token already known: rebind to current user (in case of account switch on same device)
            existing.UserId = CurrentUserId;
            existing.Platform = request.Platform.Trim().ToLowerInvariant();
            existing.DeviceName = request.DeviceName ?? existing.DeviceName;
            existing.AppVersion = request.AppVersion ?? existing.AppVersion;
            existing.IsDisabled = false;
        }
        await db.SaveChangesAsync(ct);
        return Ok(AppResponse<bool>.Success(true));
    }

    /// <summary>Unregister the FCM token (called on logout).</summary>
    [HttpDelete("device-token")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<bool>>> UnregisterDeviceToken([FromQuery] string token, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(token))
            return BadRequest(AppResponse<bool>.Fail("token query parameter is required"));

        await db.UserDeviceTokens
            .Where(t => t.Token == token && t.UserId == CurrentUserId)
            .ExecuteDeleteAsync(ct);
        return Ok(AppResponse<bool>.Success(true));
    }

    [HttpGet]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<PagedResult<NotificationDto>>>> GetUserNotifications(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20,
        [FromQuery] bool? isRead = null,
        [FromQuery] NotificationType? type = null)
    {
        var query = new GetUserNotificationsQuery(RequiredStoreId, CurrentUserId, page, pageSize, isRead, type);
        var result = await mediator.Send(query);
        return Ok(result);
    }

    [HttpGet("summary")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<NotificationSummaryDto>>> GetNotificationSummary()
    {
        var storeId = CurrentStoreId;
        if (storeId == null)
        {
            // SuperAdmin/Agent has no store - return empty summary
            return Ok(AppResponse<NotificationSummaryDto>.Success(new NotificationSummaryDto()));
        }
        var query = new GetNotificationSummaryQuery(storeId.Value, CurrentUserId);
        var result = await mediator.Send(query);
        return Ok(result);
    }

    [HttpGet("unread-count")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<int>>> GetUnreadCount()
    {
        var query = new GetUnreadCountQuery(RequiredStoreId, CurrentUserId);
        var result = await mediator.Send(query);
        return Ok(result);
    }

    [HttpGet("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<NotificationDto>>> GetNotificationById(Guid id)
    {
        var query = new GetNotificationByIdQuery(RequiredStoreId, id);
        var result = await mediator.Send(query);
        return Ok(result);
    }

    [HttpPost]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
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
    public async Task<ActionResult<AppResponse<NotificationDto>>> MarkNotificationAsRead(Guid id)
    {
        var command = new MarkNotificationReadCommand(RequiredStoreId, id, CurrentUserId);
        var result = await mediator.Send(command);
        if (result.IsSuccess)
        {
            // Broadcast to all of this user's connected clients so other devices/tabs
            // can update their unread count and mark the item as read locally.
            try
            {
                await hubContext.Clients.Group($"user_{CurrentUserId}").SendAsync(
                    "NotificationRead",
                    new { id = id.ToString(), readAt = DateTime.UtcNow });
            }
            catch { /* broadcast is best-effort */ }
        }
        return Ok(result);
    }

    [HttpPost("read-all")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<int>>> MarkAllNotificationsAsRead()
    {
        var command = new MarkAllNotificationsReadCommand(RequiredStoreId, CurrentUserId);
        var result = await mediator.Send(command);
        if (result.IsSuccess)
        {
            try
            {
                await hubContext.Clients.Group($"user_{CurrentUserId}").SendAsync(
                    "NotificationRead",
                    new { all = true, readAt = DateTime.UtcNow });
            }
            catch { /* broadcast is best-effort */ }
        }
        return Ok(result);
    }

    [HttpDelete("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<bool>>> DeleteNotification(Guid id)
    {
        var command = new DeleteNotificationCommand(RequiredStoreId, id, CurrentUserId);
        var result = await mediator.Send(command);
        return Ok(result);
    }

    [HttpDelete]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<int>>> DeleteAllNotifications([FromQuery] bool? isRead = null)
    {
        var command = new DeleteAllNotificationsCommand(RequiredStoreId, CurrentUserId, isRead);
        var result = await mediator.Send(command);
        return Ok(result);
    }
}

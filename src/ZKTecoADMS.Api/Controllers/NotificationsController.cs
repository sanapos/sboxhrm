using Microsoft.AspNetCore.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Commands.Notifications;
using ZKTecoADMS.Application.Queries.Notifications;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.DTOs.Notifications;
using ZKTecoADMS.Application.DTOs.Commons;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
public class NotificationsController(IMediator mediator) : AuthenticatedControllerBase
{
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
        var query = new GetNotificationSummaryQuery(RequiredStoreId, CurrentUserId);
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
        return Ok(result);
    }

    [HttpPost("read-all")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<int>>> MarkAllNotificationsAsRead()
    {
        var command = new MarkAllNotificationsReadCommand(RequiredStoreId, CurrentUserId);
        var result = await mediator.Send(command);
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

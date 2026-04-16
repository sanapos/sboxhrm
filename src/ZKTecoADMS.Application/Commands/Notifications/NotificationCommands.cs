using ZKTecoADMS.Application.DTOs.Notifications;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.Notifications;

// Create Notification Command
public record CreateNotificationCommand(
    Guid StoreId,
    Guid? TargetUserId,
    NotificationType Type,
    string? Title,
    string Message,
    string? RelatedUrl,
    Guid? RelatedEntityId,
    string? RelatedEntityType,
    Guid? FromUserId) : ICommand<AppResponse<NotificationDto>>;

public class CreateNotificationHandler(
    IRepository<Notification> notificationRepository
) : ICommandHandler<CreateNotificationCommand, AppResponse<NotificationDto>>
{
    public async Task<AppResponse<NotificationDto>> Handle(CreateNotificationCommand request, CancellationToken cancellationToken)
    {
        try
        {
            var notification = new Notification
            {
                StoreId = request.StoreId,
                TargetUserId = request.TargetUserId,
                Type = request.Type,
                Title = request.Title,
                Message = request.Message,
                Timestamp = DateTime.UtcNow,
                IsRead = false,
                FromUserId = request.FromUserId,
                RelatedUrl = request.RelatedUrl,
                RelatedEntityId = request.RelatedEntityId,
                RelatedEntityType = request.RelatedEntityType
            };

            var created = await notificationRepository.AddAsync(notification, cancellationToken);
            
            return AppResponse<NotificationDto>.Success(created.Adapt<NotificationDto>());
        }
        catch (Exception ex)
        {
            return AppResponse<NotificationDto>.Error(ex.Message);
        }
    }
}

// Bulk Create Notifications Command
public record BulkCreateNotificationsCommand(
    Guid StoreId,
    List<Guid> TargetUserIds,
    NotificationType Type,
    string? Title,
    string Message,
    string? RelatedUrl,
    Guid? FromUserId) : ICommand<AppResponse<List<NotificationDto>>>;

public class BulkCreateNotificationsHandler(
    IRepository<Notification> notificationRepository
) : ICommandHandler<BulkCreateNotificationsCommand, AppResponse<List<NotificationDto>>>
{
    public async Task<AppResponse<List<NotificationDto>>> Handle(BulkCreateNotificationsCommand request, CancellationToken cancellationToken)
    {
        try
        {
            var notifications = request.TargetUserIds.Select(userId => new Notification
            {
                StoreId = request.StoreId,
                TargetUserId = userId,
                Type = request.Type,
                Title = request.Title,
                Message = request.Message,
                Timestamp = DateTime.UtcNow,
                IsRead = false,
                FromUserId = request.FromUserId,
                RelatedUrl = request.RelatedUrl
            }).ToList();

            // Batch insert all notifications in one DB roundtrip
            await notificationRepository.AddRangeAsync(notifications, cancellationToken);
            
            return AppResponse<List<NotificationDto>>.Success(notifications.Adapt<List<NotificationDto>>());
        }
        catch (Exception ex)
        {
            return AppResponse<List<NotificationDto>>.Error(ex.Message);
        }
    }
}

// Mark Notification as Read Command
public record MarkNotificationReadCommand(
    Guid StoreId,
    Guid NotificationId,
    Guid UserId) : ICommand<AppResponse<NotificationDto>>;

public class MarkNotificationReadHandler(
    IRepository<Notification> notificationRepository
) : ICommandHandler<MarkNotificationReadCommand, AppResponse<NotificationDto>>
{
    public async Task<AppResponse<NotificationDto>> Handle(MarkNotificationReadCommand request, CancellationToken cancellationToken)
    {
        try
        {
            var notification = await notificationRepository.GetSingleAsync(
                filter: n => n.Id == request.NotificationId && n.StoreId == request.StoreId,
                cancellationToken: cancellationToken);
            if (notification == null)
            {
                return AppResponse<NotificationDto>.Error("Notification not found");
            }

            // Only allow marking own per-user notifications as read
            if (notification.TargetUserId != request.UserId)
            {
                return AppResponse<NotificationDto>.Error("Not authorized");
            }

            notification.IsRead = true;
            notification.ReadAt = DateTime.UtcNow;

            await notificationRepository.UpdateAsync(notification, cancellationToken);
            
            return AppResponse<NotificationDto>.Success(notification.Adapt<NotificationDto>());
        }
        catch (Exception ex)
        {
            return AppResponse<NotificationDto>.Error(ex.Message);
        }
    }
}

// Mark All Notifications as Read Command
public record MarkAllNotificationsReadCommand(Guid StoreId, Guid UserId) : ICommand<AppResponse<int>>;

public class MarkAllNotificationsReadHandler(
    IRepository<Notification> notificationRepository
) : ICommandHandler<MarkAllNotificationsReadCommand, AppResponse<int>>
{
    public async Task<AppResponse<int>> Handle(MarkAllNotificationsReadCommand request, CancellationToken cancellationToken)
    {
        try
        {
            var unreadNotifications = await notificationRepository.GetAllAsync(
                n => n.StoreId == request.StoreId &&
                     n.TargetUserId == request.UserId &&
                     !n.IsRead,
                cancellationToken: cancellationToken);

            if (unreadNotifications.Count == 0)
                return AppResponse<int>.Success(0);

            var now = DateTime.UtcNow;
            foreach (var notification in unreadNotifications)
            {
                notification.IsRead = true;
                notification.ReadAt = now;
            }

            // Batch update: single SaveChanges via UpdateRangeAsync
            await notificationRepository.UpdateRangeAsync(unreadNotifications, cancellationToken);
            
            return AppResponse<int>.Success(unreadNotifications.Count);
        }
        catch (Exception ex)
        {
            return AppResponse<int>.Error(ex.Message);
        }
    }
}

// Delete Notification Command
public record DeleteNotificationCommand(
    Guid StoreId,
    Guid NotificationId,
    Guid UserId) : ICommand<AppResponse<bool>>;

public class DeleteNotificationHandler(
    IRepository<Notification> notificationRepository
) : ICommandHandler<DeleteNotificationCommand, AppResponse<bool>>
{
    public async Task<AppResponse<bool>> Handle(DeleteNotificationCommand request, CancellationToken cancellationToken)
    {
        try
        {
            var notification = await notificationRepository.GetSingleAsync(
                filter: n => n.Id == request.NotificationId && n.StoreId == request.StoreId,
                cancellationToken: cancellationToken);
            if (notification == null)
            {
                return AppResponse<bool>.Error("Notification not found");
            }

            // Only allow deleting own per-user notifications
            if (notification.TargetUserId != request.UserId)
            {
                return AppResponse<bool>.Error("Not authorized");
            }

            await notificationRepository.DeleteAsync(notification, cancellationToken);
            
            return AppResponse<bool>.Success(true);
        }
        catch (Exception ex)
        {
            return AppResponse<bool>.Error(ex.Message);
        }
    }
}

// Delete All Notifications Command
public record DeleteAllNotificationsCommand(
    Guid StoreId,
    Guid UserId,
    bool? IsRead = null) : ICommand<AppResponse<int>>;

public class DeleteAllNotificationsHandler(
    IRepository<Notification> notificationRepository
) : ICommandHandler<DeleteAllNotificationsCommand, AppResponse<int>>
{
    public async Task<AppResponse<int>> Handle(DeleteAllNotificationsCommand request, CancellationToken cancellationToken)
    {
        try
        {
            // Count first for response, then bulk delete with filter (single SQL roundtrip)
            var isRead = request.IsRead;
            var count = await notificationRepository.CountAsync(
                n => n.StoreId == request.StoreId
                    && n.TargetUserId == request.UserId
                    && (isRead == null || n.IsRead == isRead),
                cancellationToken);

            if (count == 0)
                return AppResponse<int>.Success(0);

            await notificationRepository.DeleteAsync(
                n => n.StoreId == request.StoreId
                    && n.TargetUserId == request.UserId
                    && (isRead == null || n.IsRead == isRead),
                cancellationToken);

            return AppResponse<int>.Success(count);
        }
        catch (Exception ex)
        {
            return AppResponse<int>.Error(ex.Message);
        }
    }
}

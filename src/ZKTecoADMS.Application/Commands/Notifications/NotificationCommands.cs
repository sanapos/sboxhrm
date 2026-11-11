using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.DTOs.Notifications;
using ZKTecoADMS.Application.Notifications;
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
    IRepository<Notification> notificationRepository,
    ISystemNotificationService notificationService,
    UserManager<ApplicationUser> userManager
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

            if (request.TargetUserId is Guid target
                && (await NotificationTargetScope.InStoreAsync(userManager, [target], request.StoreId, cancellationToken)).Count == 0)
                return AppResponse<NotificationDto>.Error("Người nhận không thuộc cửa hàng");

            var created = await notificationRepository.AddAsync(notification, cancellationToken);

            // Trước đây chỉ lưu — người nhận không có thông báo trên điện thoại (SignalR + FCM).
            if (created.TargetUserId is Guid uid)
            {
                try { await notificationService.SendToUserAsync(uid, created); }
                catch { /* đẩy lỗi không làm hỏng việc tạo; thông báo vẫn trong danh sách */ }
            }
            
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
    IRepository<Notification> notificationRepository,
    ISystemNotificationService notificationService,
    UserManager<ApplicationUser> userManager
) : ICommandHandler<BulkCreateNotificationsCommand, AppResponse<List<NotificationDto>>>
{
    public async Task<AppResponse<List<NotificationDto>>> Handle(BulkCreateNotificationsCommand request, CancellationToken cancellationToken)
    {
        try
        {
            // Chỉ người nhận thuộc cửa hàng (trước đây nhận mọi mã tài khoản gửi lên).
            var targets = await NotificationTargetScope.InStoreAsync(
                userManager, request.TargetUserIds.Distinct().ToList(), request.StoreId, cancellationToken);
            var notifications = targets.Select(userId => new Notification
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

            if (notifications.Count > 0)
                await notificationRepository.AddRangeAsync(notifications, cancellationToken);

            // Đẩy từng người (mỗi máy nhận đúng mã thông báo của mình). Trước đây chỉ lưu.
            foreach (var n in notifications)
            {
                try { await notificationService.SendToUserAsync(n.TargetUserId!.Value, n); }
                catch { /* lỗi đẩy một người không chặn người khác */ }
            }
            
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
    Guid NotificationId,
    Guid UserId,
    Guid? StoreId,
    bool IsCrossStoreUser) : ICommand<AppResponse<NotificationDto>>;

public class MarkNotificationReadHandler(
    IRepository<Notification> notificationRepository
) : ICommandHandler<MarkNotificationReadCommand, AppResponse<NotificationDto>>
{
    public async Task<AppResponse<NotificationDto>> Handle(MarkNotificationReadCommand request, CancellationToken cancellationToken)
    {
        try
        {
            var filter = NotificationUserScope.FilterById(
                request.NotificationId, request.UserId, request.StoreId, request.IsCrossStoreUser);

            var notification = await notificationRepository.GetSingleAsync(
                filter: filter,
                cancellationToken: cancellationToken);
            if (notification == null)
            {
                return AppResponse<NotificationDto>.Error("Notification not found");
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
public record MarkAllNotificationsReadCommand(
    Guid UserId,
    Guid? StoreId,
    bool IsCrossStoreUser) : ICommand<AppResponse<int>>;

public class MarkAllNotificationsReadHandler(
    IRepository<Notification> notificationRepository
) : ICommandHandler<MarkAllNotificationsReadCommand, AppResponse<int>>
{
    public async Task<AppResponse<int>> Handle(MarkAllNotificationsReadCommand request, CancellationToken cancellationToken)
    {
        try
        {
            var unreadNotifications = await notificationRepository.GetAllAsync(
                NotificationUserScope.FilterForUser(
                    request.UserId, request.StoreId, request.IsCrossStoreUser, isRead: false),
                cancellationToken: cancellationToken);

            if (unreadNotifications.Count == 0)
                return AppResponse<int>.Success(0);

            var now = DateTime.UtcNow;
            foreach (var notification in unreadNotifications)
            {
                notification.IsRead = true;
                notification.ReadAt = now;
            }

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
    Guid NotificationId,
    Guid UserId,
    Guid? StoreId,
    bool IsCrossStoreUser) : ICommand<AppResponse<bool>>;

public class DeleteNotificationHandler(
    IRepository<Notification> notificationRepository
) : ICommandHandler<DeleteNotificationCommand, AppResponse<bool>>
{
    public async Task<AppResponse<bool>> Handle(DeleteNotificationCommand request, CancellationToken cancellationToken)
    {
        try
        {
            var filter = NotificationUserScope.FilterById(
                request.NotificationId, request.UserId, request.StoreId, request.IsCrossStoreUser);

            var notification = await notificationRepository.GetSingleAsync(
                filter: filter,
                cancellationToken: cancellationToken);
            if (notification == null)
            {
                return AppResponse<bool>.Error("Notification not found");
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
    Guid UserId,
    Guid? StoreId,
    bool IsCrossStoreUser,
    bool? IsRead = null) : ICommand<AppResponse<int>>;

public class DeleteAllNotificationsHandler(
    IRepository<Notification> notificationRepository
) : ICommandHandler<DeleteAllNotificationsCommand, AppResponse<int>>
{
    public async Task<AppResponse<int>> Handle(DeleteAllNotificationsCommand request, CancellationToken cancellationToken)
    {
        try
        {
            var isRead = request.IsRead;
            var toDelete = await notificationRepository.GetAllAsync(
                NotificationUserScope.FilterForUser(
                    request.UserId, request.StoreId, request.IsCrossStoreUser, isRead: isRead),
                cancellationToken: cancellationToken);

            if (toDelete.Count == 0)
                return AppResponse<int>.Success(0);

            var count = toDelete.Count;
            await notificationRepository.DeleteAsync(
                NotificationUserScope.FilterForUser(
                    request.UserId, request.StoreId, request.IsCrossStoreUser, isRead: isRead),
                cancellationToken);

            return AppResponse<int>.Success(count);
        }
        catch (Exception ex)
        {
            return AppResponse<int>.Error(ex.Message);
        }
    }
}

/// <summary>Lọc người nhận về tài khoản của cửa hàng gửi thông báo.</summary>
internal static class NotificationTargetScope
{
    public static async Task<List<Guid>> InStoreAsync(
        UserManager<ApplicationUser> userManager, IReadOnlyCollection<Guid> userIds, Guid storeId, CancellationToken ct)
    {
        if (userIds.Count == 0) return [];
        var ids = userIds.ToList();
        return await userManager.Users.AsNoTracking()
            .Where(u => ids.Contains(u.Id) && u.StoreId == storeId)
            .Select(u => u.Id)
            .ToListAsync(ct);
    }
}

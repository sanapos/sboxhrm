using System.Linq.Expressions;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.DTOs.Notifications;
using ZKTecoADMS.Application.DTOs.Commons;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Queries.Notifications;

// Get User Notifications Query
public record GetUserNotificationsQuery(
    Guid StoreId,
    Guid UserId,
    int Page = 1,
    int PageSize = 20,
    bool? IsRead = null,
    NotificationType? Type = null) : IQuery<AppResponse<PagedResult<NotificationDto>>>;

public class GetUserNotificationsHandler(
    IRepository<Notification> notificationRepository
) : IQueryHandler<GetUserNotificationsQuery, AppResponse<PagedResult<NotificationDto>>>
{
    public async Task<AppResponse<PagedResult<NotificationDto>>> Handle(GetUserNotificationsQuery request, CancellationToken cancellationToken)
    {
        try
        {
            // Only fetch notifications targeted to this specific user (per-user records)
            Expression<Func<Notification, bool>> filter = n => 
                n.StoreId == request.StoreId &&
                n.TargetUserId == request.UserId;

            if (request.IsRead.HasValue || request.Type.HasValue)
            {
                var isRead = request.IsRead;
                var type = request.Type;
                filter = n => n.StoreId == request.StoreId &&
                             n.TargetUserId == request.UserId &&
                             (!isRead.HasValue || n.IsRead == isRead.Value) &&
                             (!type.HasValue || n.Type == type.Value);
            }

            var totalCount = await notificationRepository.CountAsync(filter, cancellationToken);

            var items = await notificationRepository.GetAllWithIncludeAsync(
                filter: filter,
                orderBy: q => q.OrderByDescending(n => n.Timestamp),
                includes: q => q.Include(n => n.TargetUser).Include(n => n.FromUser),
                skip: (request.Page - 1) * request.PageSize,
                take: request.PageSize,
                cancellationToken: cancellationToken);

            var result = new PagedResult<NotificationDto>(
                items.Adapt<List<NotificationDto>>(),
                totalCount,
                request.Page,
                request.PageSize);

            return AppResponse<PagedResult<NotificationDto>>.Success(result);
        }
        catch (Exception ex)
        {
            return AppResponse<PagedResult<NotificationDto>>.Error(ex.Message);
        }
    }
}

// Get Notification by Id Query
public record GetNotificationByIdQuery(Guid StoreId, Guid Id) : IQuery<AppResponse<NotificationDto>>;

public class GetNotificationByIdHandler(
    IRepository<Notification> notificationRepository
) : IQueryHandler<GetNotificationByIdQuery, AppResponse<NotificationDto>>
{
    public async Task<AppResponse<NotificationDto>> Handle(GetNotificationByIdQuery request, CancellationToken cancellationToken)
    {
        try
        {
            var notification = await notificationRepository.GetSingleAsync(
                filter: n => n.Id == request.Id && n.StoreId == request.StoreId, 
                includeProperties: ["TargetUser", "FromUser"],
                cancellationToken: cancellationToken);
            
            if (notification == null)
            {
                return AppResponse<NotificationDto>.Error("Notification not found");
            }

            return AppResponse<NotificationDto>.Success(notification.Adapt<NotificationDto>());
        }
        catch (Exception ex)
        {
            return AppResponse<NotificationDto>.Error(ex.Message);
        }
    }
}

// Get Notification Summary (Unread Count by Type)
public record GetNotificationSummaryQuery(Guid StoreId, Guid UserId) : IQuery<AppResponse<NotificationSummaryDto>>;

public class GetNotificationSummaryHandler(
    IRepository<Notification> notificationRepository
) : IQueryHandler<GetNotificationSummaryQuery, AppResponse<NotificationSummaryDto>>
{
    public async Task<AppResponse<NotificationSummaryDto>> Handle(GetNotificationSummaryQuery request, CancellationToken cancellationToken)
    {
        try
        {
            Expression<Func<Notification, bool>> baseFilter = n => 
                n.StoreId == request.StoreId && 
                n.TargetUserId == request.UserId;

            // Use COUNT queries instead of loading all records into memory
            var totalCount = await notificationRepository.CountAsync(baseFilter, cancellationToken);

            var unreadCount = await notificationRepository.CountAsync(
                n => n.StoreId == request.StoreId 
                     && n.TargetUserId == request.UserId 
                     && !n.IsRead,
                cancellationToken);

            // Only load the 5 most recent notifications
            var recentNotifications = await notificationRepository.GetAllAsync(
                filter: baseFilter,
                orderBy: q => q.OrderByDescending(n => n.Timestamp),
                take: 5,
                cancellationToken: cancellationToken);

            var summary = new NotificationSummaryDto
            {
                TotalCount = totalCount,
                UnreadCount = unreadCount,
                RecentNotifications = recentNotifications.Adapt<List<NotificationDto>>()
            };

            return AppResponse<NotificationSummaryDto>.Success(summary);
        }
        catch (Exception ex)
        {
            return AppResponse<NotificationSummaryDto>.Error(ex.Message);
        }
    }
}

// Get Unread Count (lightweight for badge)
public record GetUnreadCountQuery(Guid StoreId, Guid UserId) : IQuery<AppResponse<int>>;

public class GetUnreadCountHandler(
    IRepository<Notification> notificationRepository
) : IQueryHandler<GetUnreadCountQuery, AppResponse<int>>
{
    public async Task<AppResponse<int>> Handle(GetUnreadCountQuery request, CancellationToken cancellationToken)
    {
        try
        {
            var count = await notificationRepository.CountAsync(
                n => n.StoreId == request.StoreId 
                     && n.TargetUserId == request.UserId 
                     && !n.IsRead,
                cancellationToken);
            return AppResponse<int>.Success(count);
        }
        catch (Exception ex)
        {
            return AppResponse<int>.Error(ex.Message);
        }
    }
}

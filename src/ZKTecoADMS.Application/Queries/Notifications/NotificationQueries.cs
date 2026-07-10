using System.Linq.Expressions;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.Notifications;
using ZKTecoADMS.Application.DTOs.Notifications;
using ZKTecoADMS.Application.DTOs.Commons;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Queries.Notifications;

// Get User Notifications Query
public record GetUserNotificationsQuery(
    Guid UserId,
    Guid? StoreId,
    bool IsCrossStoreUser,
    int Page = 1,
    int PageSize = 20,
    bool? IsRead = null,
    NotificationType? Type = null) : IQuery<AppResponse<PagedResult<NotificationDto>>>;

internal static class NotificationVisibilityFilter
{
    public static async Task<List<Notification>> FilterOrphanAttendanceAsync(
        List<Notification> items,
        IRepository<Attendance> attendanceRepository,
        CancellationToken cancellationToken)
    {
        var attendanceNotifs = items
            .Where(n => n.RelatedEntityType == "Attendance" && n.RelatedEntityId.HasValue)
            .ToList();
        if (attendanceNotifs.Count == 0) return items;

        var relatedIds = attendanceNotifs.Select(n => n.RelatedEntityId!.Value).Distinct().ToList();
        var existing = (await attendanceRepository.GetAllAsync(
                a => relatedIds.Contains(a.Id),
                cancellationToken: cancellationToken))
            .Select(a => a.Id)
            .ToHashSet();

        return items
            .Where(n => n.RelatedEntityType != "Attendance"
                        || !n.RelatedEntityId.HasValue
                        || existing.Contains(n.RelatedEntityId.Value))
            .ToList();
    }
}

public class GetUserNotificationsHandler(
    IRepository<Notification> notificationRepository,
    IRepository<Attendance> attendanceRepository
) : IQueryHandler<GetUserNotificationsQuery, AppResponse<PagedResult<NotificationDto>>>
{
    public async Task<AppResponse<PagedResult<NotificationDto>>> Handle(GetUserNotificationsQuery request, CancellationToken cancellationToken)
    {
        try
        {
            Expression<Func<Notification, bool>> filter = NotificationUserScope.FilterForUser(
                request.UserId, request.StoreId, request.IsCrossStoreUser,
                request.IsRead, request.Type);

            var items = await notificationRepository.GetAllWithIncludeAsync(
                filter: filter,
                orderBy: q => q.OrderByDescending(n => n.Timestamp),
                includes: q => q.Include(n => n.TargetUser).Include(n => n.FromUser),
                skip: 0,
                take: 5000,
                cancellationToken: cancellationToken);

            var visible = await NotificationVisibilityFilter.FilterOrphanAttendanceAsync(
                items, attendanceRepository, cancellationToken);
            var totalCount = visible.Count;

            var page = Math.Max(1, request.Page);
            var pageSize = Math.Clamp(request.PageSize, 1, 100);
            var paged = visible
                .Skip((page - 1) * pageSize)
                .Take(pageSize)
                .ToList();

            var dtos = paged.Adapt<List<NotificationDto>>();
            for (var i = 0; i < paged.Count; i++)
            {
                var entity = paged[i];
                var dto = dtos[i];
                var senderName = NotificationPushFormatter.FormatUserDisplayName(entity.FromUser);
                var display = NotificationPushFormatter.Format(entity, senderName);
                dto.FromUserName = string.IsNullOrWhiteSpace(senderName) ? null : senderName;
                dto.CategoryLabel = display.CategoryLabel;
                dto.DisplayTitle = display.Title;
                dto.DisplayBody = display.Body;
            }

            var result = new PagedResult<NotificationDto>(
                dtos,
                totalCount,
                page,
                pageSize);

            return AppResponse<PagedResult<NotificationDto>>.Success(result);
        }
        catch (Exception ex)
        {
            return AppResponse<PagedResult<NotificationDto>>.Error(ex.Message);
        }
    }

}

// Get Notification by Id Query
public record GetNotificationByIdQuery(
    Guid Id,
    Guid UserId,
    Guid? StoreId,
    bool IsCrossStoreUser) : IQuery<AppResponse<NotificationDto>>;

public class GetNotificationByIdHandler(
    IRepository<Notification> notificationRepository
) : IQueryHandler<GetNotificationByIdQuery, AppResponse<NotificationDto>>
{
    public async Task<AppResponse<NotificationDto>> Handle(GetNotificationByIdQuery request, CancellationToken cancellationToken)
    {
        try
        {
            var filter = NotificationUserScope.FilterById(
                request.Id, request.UserId, request.StoreId, request.IsCrossStoreUser);

            var notification = await notificationRepository.GetSingleAsync(
                filter: filter,
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
public record GetNotificationSummaryQuery(
    Guid UserId,
    Guid? StoreId,
    bool IsCrossStoreUser) : IQuery<AppResponse<NotificationSummaryDto>>;

public class GetNotificationSummaryHandler(
    IRepository<Notification> notificationRepository,
    IRepository<Attendance> attendanceRepository
) : IQueryHandler<GetNotificationSummaryQuery, AppResponse<NotificationSummaryDto>>
{
    public async Task<AppResponse<NotificationSummaryDto>> Handle(GetNotificationSummaryQuery request, CancellationToken cancellationToken)
    {
        try
        {
            Expression<Func<Notification, bool>> baseFilter = NotificationUserScope.FilterForUser(
                request.UserId, request.StoreId, request.IsCrossStoreUser);

            var allForUser = await notificationRepository.GetAllAsync(
                filter: baseFilter,
                orderBy: q => q.OrderByDescending(n => n.Timestamp),
                take: 5000,
                cancellationToken: cancellationToken);

            var visible = await NotificationVisibilityFilter.FilterOrphanAttendanceAsync(
                allForUser, attendanceRepository, cancellationToken);

            var totalCount = visible.Count;
            var unreadCount = visible.Count(n => !n.IsRead);

            var recentNotifications = visible.Take(5).ToList();

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
public record GetUnreadCountQuery(
    Guid UserId,
    Guid? StoreId,
    bool IsCrossStoreUser) : IQuery<AppResponse<int>>;

public class GetUnreadCountHandler(
    IRepository<Notification> notificationRepository,
    IRepository<Attendance> attendanceRepository
) : IQueryHandler<GetUnreadCountQuery, AppResponse<int>>
{
    public async Task<AppResponse<int>> Handle(GetUnreadCountQuery request, CancellationToken cancellationToken)
    {
        try
        {
            var unread = await notificationRepository.GetAllAsync(
                filter: NotificationUserScope.FilterForUser(
                    request.UserId, request.StoreId, request.IsCrossStoreUser, isRead: false),
                take: 5000,
                cancellationToken: cancellationToken);

            var visible = await NotificationVisibilityFilter.FilterOrphanAttendanceAsync(
                unread, attendanceRepository, cancellationToken);

            return AppResponse<int>.Success(visible.Count);
        }
        catch (Exception ex)
        {
            return AppResponse<int>.Error(ex.Message);
        }
    }
}

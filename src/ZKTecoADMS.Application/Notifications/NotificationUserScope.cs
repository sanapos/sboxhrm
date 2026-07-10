using System.Linq.Expressions;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Notifications;

/// <summary>
/// SuperAdmin/Agent không gắn store — lọc thông báo theo TargetUserId thay vì StoreId.
/// </summary>
public static class NotificationUserScope
{
    public static bool IsCrossStoreUser(string? role) =>
        string.Equals(role, nameof(Roles.SuperAdmin), StringComparison.OrdinalIgnoreCase)
        || string.Equals(role, nameof(Roles.Agent), StringComparison.OrdinalIgnoreCase);

    public static Expression<Func<Notification, bool>> FilterForUser(
        Guid userId,
        Guid? storeId,
        bool crossStore,
        bool? isRead = null,
        NotificationType? type = null) =>
        n => n.TargetUserId == userId
             && (crossStore || n.StoreId == storeId)
             && (!isRead.HasValue || n.IsRead == isRead.Value)
             && (!type.HasValue || n.Type == type.Value);

    public static Expression<Func<Notification, bool>> FilterById(
        Guid notificationId,
        Guid userId,
        Guid? storeId,
        bool crossStore) =>
        crossStore
            ? n => n.Id == notificationId && n.TargetUserId == userId
            : n => n.Id == notificationId && n.StoreId == storeId && n.TargetUserId == userId;
}

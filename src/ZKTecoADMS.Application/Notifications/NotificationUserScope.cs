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
        NotificationType? type = null,
        IReadOnlyCollection<string>? categories = null,
        string? search = null)
    {
        // Lọc nhóm loại phía server (trước đây app lọc trên trang đã tải → thiếu kết quả).
        var cats = categories is { Count: > 0 } ? categories.ToList() : null;
        var includeUncategorized = cats != null && cats.Contains(UncategorizedCode);
        var q = string.IsNullOrWhiteSpace(search) ? null : search.Trim().ToLower();
        return n => n.TargetUserId == userId
             && (crossStore
                 || n.StoreId == storeId
                 || n.StoreId == null)
             && (!isRead.HasValue || n.IsRead == isRead.Value)
             && (!type.HasValue || n.Type == type.Value)
             && (cats == null
                 || (n.CategoryCode != null && cats.Contains(n.CategoryCode))
                 || (includeUncategorized && n.CategoryCode == null))
             && (q == null || n.Title.ToLower().Contains(q) || n.Message.ToLower().Contains(q));
    }

    /// <summary>Mã giả cho thông báo cũ chưa gắn loại.</summary>
    public const string UncategorizedCode = "none";

    public static Expression<Func<Notification, bool>> FilterById(
        Guid notificationId,
        Guid userId,
        Guid? storeId,
        bool crossStore) =>
        crossStore
            ? n => n.Id == notificationId && n.TargetUserId == userId
            : n => n.Id == notificationId && n.TargetUserId == userId
                   && (n.StoreId == storeId || n.StoreId == null);
}

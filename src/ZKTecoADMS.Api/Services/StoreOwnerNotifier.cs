using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Services;

/// <summary>Gửi cảnh báo cho chủ cửa hàng / giám đốc của đúng cửa hàng (không phát cho mọi người).</summary>
public static class StoreOwnerNotifier
{
    static readonly string[] OwnerRoles = [nameof(Roles.Admin), nameof(Roles.Director)];

    public static async Task NotifyAsync(ZKTecoDbContext db, ISystemNotificationService notifications, Guid storeId,
        string title, string message, string relatedEntityType, Guid? fromUserId)
    {
        try
        {
            var owners = await db.Users.AsNoTracking()
                .Where(u => u.StoreId == storeId && OwnerRoles.Contains(u.Role))
                .Select(u => u.Id)
                .ToListAsync();
            if (owners.Count == 0) return;
            await notifications.CreateAndSendToUsersAsync(owners, NotificationType.Warning, title, message,
                relatedEntityType: relatedEntityType, fromUserId: fromUserId, categoryCode: "system", storeId: storeId);
        }
        catch
        {
            // Không chặn thao tác nếu gửi thông báo lỗi.
        }
    }
}

using System.Text.RegularExpressions;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.Helpers;
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
            // Người vừa thao tác đã biết — chỉ báo các chủ / giám đốc còn lại.
            var owners = await db.Users.AsNoTracking()
                .Where(u => u.IsActive && u.StoreId == storeId && OwnerRoles.Contains(u.Role)
                    && (fromUserId == null || u.Id != fromUserId))
                .Select(u => u.Id)
                .ToListAsync();
            if (owners.Count == 0) return;
            message = CleanMessage(message, fromUserId.HasValue);
            await notifications.CreateAndSendToUsersAsync(owners, NotificationType.Warning, title, message,
                relatedEntityType: relatedEntityType, fromUserId: fromUserId, categoryCode: "system", storeId: storeId);
        }
        catch
        {
            // Không chặn thao tác nếu gửi thông báo lỗi.
        }
    }

    static readonly Regex ByActorSuffix = new(@"\s*[—–-]\s*bởi\s+.*$", RegexOptions.Compiled | RegexOptions.IgnoreCase);
    static readonly Regex ProviderCode = new(@"\((vietqr|tingee)\)", RegexOptions.Compiled | RegexOptions.IgnoreCase);

    /// <summary>
    /// Người gọi ghép «— bởi {email}» vào cuối: formatter đã thêm tên người thao tác (fromUserId) nên bỏ email
    /// (trước đây «Trần Thị Bích: … — bởi bich@gmail.com»). Mã nhà cung cấp → tên hiển thị; thêm giờ VN.
    /// </summary>
    static string CleanMessage(string message, bool hasSender)
    {
        var text = (message ?? string.Empty).Trim();
        if (hasSender) text = ByActorSuffix.Replace(text, string.Empty);
        text = ProviderCode.Replace(text, m =>
            m.Groups[1].Value.Equals("tingee", StringComparison.OrdinalIgnoreCase) ? "(Tingee)" : "(VietQR)");
        return $"{text} · lúc {VnTimeHelper.NowVn():HH:mm dd/MM}";
    }
}

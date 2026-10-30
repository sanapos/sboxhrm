using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Services;

internal static class PosNotificationHelper
{
    private static readonly string[] ManagerRoles =
    [
        nameof(Roles.Admin),
        nameof(Roles.Director),
        nameof(Roles.Manager),
        nameof(Roles.DepartmentHead),
    ];

    /// <summary>Thu ngân / phục vụ / quản lý — nhận FCM đơn QR và đặt lịch khi app tắt.</summary>
    private static readonly string[] FrontlineRoles =
    [
        nameof(Roles.Admin),
        nameof(Roles.Director),
        nameof(Roles.Manager),
        nameof(Roles.DepartmentHead),
        nameof(Roles.Cashier),
        nameof(Roles.Waiter),
    ];

    public static async Task NotifySaleCompletedAsync(
        ISystemNotificationService notifications,
        ZKTecoDbContext db,
        Guid storeId,
        Guid orderId,
        string orderNo,
        decimal total,
        string? soldBy,
        Guid? fromUserId,
        CancellationToken cancellationToken = default)
    {
        try
        {
            // Chỉ quản lý (+ chủ nếu đúng cửa hàng): số tiền từng đơn là doanh số cửa hàng, thu ngân /
            // phục vụ không cần thấy đơn của người khác (họ xem đơn mình trên màn bán hàng).
            var userIds = await GetPosManagerUserIdsAsync(db, storeId, cancellationToken);
            if (await OwnerAtStoreAsync(db, storeId, cancellationToken) is Guid owner && !userIds.Contains(owner))
                userIds.Add(owner);
            // Người vừa bán đã thấy kết quả ngay trên màn hình — không đẩy lại popup cho chính họ.
            if (fromUserId.HasValue) userIds = userIds.Where(u => u != fromUserId.Value).ToList();
            if (userIds.Count == 0) return;

            var seller = string.IsNullOrWhiteSpace(soldBy) ? "—" : soldBy.Trim();
            var title = "Bán hàng POS";
            var message = $"Đơn {orderNo} — {total:N0}đ — NV: {seller}";

            await notifications.CreateAndSendToUsersAsync(
                userIds,
                NotificationType.Info,
                title,
                message,
                relatedEntityId: orderId,
                relatedEntityType: "PosSaleOrder",
                fromUserId: fromUserId,
                categoryCode: "pos",
                storeId: storeId);
        }
        catch
        {
            // Notification failure must not affect POS checkout.
        }
    }

    public static async Task NotifyPurchaseReceiptCompletedAsync(
        ISystemNotificationService notifications,
        ZKTecoDbContext db,
        Guid storeId,
        Guid receiptId,
        string receiptNo,
        decimal grandTotal,
        string? supplierName,
        Guid? fromUserId,
        CancellationToken cancellationToken = default)
    {
        try
        {
            var userIds = await GetPosManagerUserIdsAsync(db, storeId, cancellationToken);
            if (userIds.Count == 0) return;

            var supplier = string.IsNullOrWhiteSpace(supplierName) ? "—" : supplierName.Trim();
            var title = "Nhập hàng POS";
            var message = $"Phiếu {receiptNo} — {grandTotal:N0}đ — NCC: {supplier}";

            await notifications.CreateAndSendToUsersAsync(
                userIds,
                NotificationType.Info,
                title,
                message,
                relatedEntityId: receiptId,
                relatedEntityType: "PosPurchaseReceipt",
                fromUserId: fromUserId,
                categoryCode: "pos",
                storeId: storeId);
        }
        catch
        {
            // Notification failure must not affect receipt completion.
        }
    }

    public static async Task NotifyLowStockAsync(
        ISystemNotificationService notifications,
        ZKTecoDbContext db,
        Guid storeId,
        IEnumerable<(Guid ProductId, string ProductName, decimal OnHand, decimal MinStock)> items,
        Guid? fromUserId,
        CancellationToken cancellationToken = default)
    {
        try
        {
            var lowAll = items
                .Where(i => i.MinStock > 0 && i.OnHand <= i.MinStock)
                .ToList();
            if (lowAll.Count == 0) return;

            // Chỉ báo mặt hàng chưa được báo «Tồn kho thấp» trong ngày (mỗi đơn bán trước đây đều báo lại).
            var dayStartUtc = (DateTime.UtcNow + TimeSpan.FromHours(7)).Date - TimeSpan.FromHours(7);
            var todayMsgs = await db.Notifications.AsNoTracking()
                .Where(n => n.StoreId == storeId && n.Title == "Tồn kho thấp" && n.Timestamp >= dayStartUtc)
                .Select(n => n.Message)
                .ToListAsync(cancellationToken);
            var lowItems = lowAll
                .Where(i => !todayMsgs.Any(m => m.Contains(i.ProductName, StringComparison.OrdinalIgnoreCase)))
                .Take(2)
                .ToList();
            if (lowItems.Count == 0) return;

            var userIds = await GetPosManagerUserIdsAsync(db, storeId, cancellationToken);
            if (fromUserId.HasValue) userIds = userIds.Where(u => u != fromUserId.Value).ToList();
            if (userIds.Count == 0) return;

            var preview = string.Join(", ",
                lowItems.Select(i => $"{i.ProductName} ({i.OnHand:N0}/{i.MinStock:N0})"));
            var suffix = lowAll.Count > lowItems.Count ? $"… (+{lowAll.Count - lowItems.Count})" : "";

            await notifications.CreateAndSendToUsersAsync(
                userIds,
                NotificationType.Warning,
                "Tồn kho thấp",
                $"{preview}{suffix}",
                relatedEntityId: lowItems[0].ProductId,
                relatedEntityType: "PosProduct",
                fromUserId: fromUserId,
                categoryCode: "pos",
                storeId: storeId);
        }
        catch
        {
            // Notification failure must not affect stock updates.
        }
    }

    public static async Task NotifyQrOnlineOrderAsync(
        ISystemNotificationService notifications,
        ZKTecoDbContext db,
        Guid storeId,
        Guid orderId,
        string orderNo,
        string customerName,
        string phone,
        decimal total,
        CancellationToken cancellationToken = default)
    {
        try
        {
            var userIds = await GetPosOpsUserIdsAsync(
                db, storeId, cancellationToken, "PosQrOrder", "PosSell", "PosKds");
            if (userIds.Count == 0) return;

            var title = "Đơn online mới";
            var message =
                $"{orderNo} · {customerName} · {phone} · {total:N0}đ — gọi lại khách xác nhận";

            await notifications.CreateAndSendToUsersAsync(
                userIds,
                NotificationType.Info,
                title,
                message,
                relatedEntityId: orderId,
                relatedEntityType: "PosQrOnlineOrder",
                fromUserId: null,
                categoryCode: "pos",
                storeId: storeId);
        }
        catch
        {
            // Notification failure must not affect QR online submit.
        }
    }

    public static async Task NotifyQrTableOrderAsync(
        ISystemNotificationService notifications,
        ZKTecoDbContext db,
        Guid storeId,
        Guid orderId,
        string orderNo,
        string tableName,
        string itemPreview,
        bool needsConfirm,
        CancellationToken cancellationToken = default)
    {
        try
        {
            var userIds = await GetPosOpsUserIdsAsync(
                db, storeId, cancellationToken, "PosQrOrder", "PosSell", "PosKds");
            if (userIds.Count == 0) return;

            var title = needsConfirm ? "Đơn QR chờ xác nhận" : "Đơn QR bàn";
            var preview = string.IsNullOrWhiteSpace(itemPreview) ? "có món mới" : itemPreview.Trim();
            var message = $"{tableName} · {orderNo} · {preview}";

            await notifications.CreateAndSendToUsersAsync(
                userIds,
                NotificationType.Info,
                title,
                message,
                relatedEntityId: orderId,
                relatedEntityType: "PosQrTableOrder",
                fromUserId: null,
                categoryCode: "pos",
                storeId: storeId);
        }
        catch
        {
            // Notification failure must not affect QR table submit.
        }
    }

    public static async Task NotifyReservationCreatedAsync(
        ISystemNotificationService notifications,
        ZKTecoDbContext db,
        Guid storeId,
        Guid reservationId,
        string resourceName,
        string customerName,
        string? phone,
        DateTime reservedAt,
        int guestCount,
        bool hasPreOrder,
        Guid? fromUserId,
        CancellationToken cancellationToken = default)
    {
        try
        {
            var userIds = await GetPosOpsUserIdsAsync(
                db, storeId, cancellationToken, "PosBooking", "PosSell");
            if (userIds.Count == 0) return;

            var phonePart = string.IsNullOrWhiteSpace(phone) ? "" : $" · {phone.Trim()}";
            var prePart = hasPreOrder ? " · có đặt món" : "";
            var guests = guestCount < 1 ? 1 : guestCount;
            var message =
                $"{resourceName} · {customerName}{phonePart} · {reservedAt:dd/MM HH:mm} · {guests} khách{prePart}";

            await notifications.CreateAndSendToUsersAsync(
                userIds,
                NotificationType.Info,
                "Đặt lịch mới",
                message,
                relatedEntityId: reservationId,
                relatedEntityType: "PosResourceReservation",
                fromUserId: fromUserId,
                categoryCode: "pos",
                storeId: storeId);
        }
        catch
        {
            // Notification failure must not affect reservation create.
        }
    }

    /// <summary>«Gửi thu ngân» từ tài khoản Order → người có quyền thanh toán (PosSell · Duyệt), chủ / quản lý.</summary>
    public static async Task NotifyPaymentRequestedAsync(
        ISystemNotificationService notifications,
        ZKTecoDbContext db,
        Guid storeId,
        Guid orderId,
        string message,
        Guid? fromUserId,
        CancellationToken cancellationToken = default)
    {
        try
        {
            var payRoles = await (
                from rp in db.RolePermissions.AsNoTracking()
                join p in db.Permissions.AsNoTracking() on rp.PermissionId equals p.Id
                where rp.IsActive && rp.CanApprove && p.Module == "PosSell"
                    && (rp.StoreId == storeId || rp.StoreId == null)
                select rp.RoleName
            ).Distinct().ToListAsync(cancellationToken);
            payRoles.AddRange([nameof(Roles.Admin), nameof(Roles.Director), nameof(Roles.Manager)]);
            var userIds = await db.Users.AsNoTracking()
                .Where(u => u.IsActive && u.StoreId == storeId && payRoles.Contains(u.Role)
                    && (fromUserId == null || u.Id != fromUserId))
                .Select(u => u.Id)
                .ToListAsync(cancellationToken);
            if (userIds.Count == 0) return;

            await notifications.CreateAndSendToUsersAsync(
                userIds,
                NotificationType.Info,
                "Gửi thu ngân",
                message,
                relatedEntityId: orderId,
                relatedEntityType: "PosSaleOrder",
                fromUserId: fromUserId,
                categoryCode: "pos",
                storeId: storeId);
        }
        catch
        {
            // Lỗi gửi thông báo không làm hỏng thao tác gửi thu ngân (sơ đồ bàn đã báo realtime).
        }
    }

    private static async Task<List<Guid>> GetPosOpsUserIdsAsync(
        ZKTecoDbContext db,
        Guid storeId,
        CancellationToken cancellationToken,
        params string[] extraModules)
    {
        var ids = new HashSet<Guid>();

        var roleUsers = await db.Users.AsNoTracking()
            .Where(u => u.IsActive && u.StoreId == storeId && FrontlineRoles.Contains(u.Role))
            .Select(u => u.Id)
            .ToListAsync(cancellationToken);
        foreach (var id in roleUsers)
            ids.Add(id);

        if (await OwnerAtStoreAsync(db, storeId, cancellationToken) is Guid oid)
            ids.Add(oid);

        if (extraModules.Length > 0)
        {
            var rolesWithMod = await (
                from rp in db.RolePermissions.AsNoTracking()
                join p in db.Permissions.AsNoTracking() on rp.PermissionId equals p.Id
                where rp.IsActive && rp.CanView
                    && (rp.StoreId == storeId || rp.StoreId == null)
                    && extraModules.Contains(p.Module)
                select rp.RoleName
            ).Distinct().ToListAsync(cancellationToken);
            if (rolesWithMod.Count > 0)
            {
                var extra = await db.Users.AsNoTracking()
                    .Where(u => u.IsActive && u.StoreId == storeId && rolesWithMod.Contains(u.Role))
                    .Select(u => u.Id)
                    .ToListAsync(cancellationToken);
                foreach (var uid in extra)
                    ids.Add(uid);
            }
        }

        return ids.ToList();
    }

    /// <summary>
    /// Chủ cửa hàng, chỉ khi chủ đang trực thuộc đúng cửa hàng này. Chủ sở hữu nhiều cửa hàng
    /// có StoreId trỏ 1 cửa hàng — tránh điện thoại chủ bị dội QR/đặt lịch/bán hàng của
    /// mọi cửa hàng mình sở hữu (nhận "lung tung từ các shop khác").
    /// </summary>
    private static async Task<Guid?> OwnerAtStoreAsync(
        ZKTecoDbContext db,
        Guid storeId,
        CancellationToken cancellationToken)
    {
        var ownerId = await db.Stores.AsNoTracking()
            .Where(s => s.Id == storeId)
            .Select(s => s.OwnerId)
            .FirstOrDefaultAsync(cancellationToken);
        if (ownerId is not Guid oid || oid == Guid.Empty) return null;
        var atStore = await db.Users.AsNoTracking()
            .AnyAsync(u => u.Id == oid && u.StoreId == storeId, cancellationToken);
        return atStore ? oid : null;
    }

    internal static async Task<List<Guid>> GetPosManagerUserIdsAsync(
        ZKTecoDbContext db,
        Guid storeId,
        CancellationToken cancellationToken)
    {
        return await db.Users.AsNoTracking()
            .Where(u => u.IsActive && u.StoreId == storeId &&
                        ManagerRoles.Contains(u.Role))
            .Select(u => u.Id)
            .Distinct()
            .ToListAsync(cancellationToken);
    }
}

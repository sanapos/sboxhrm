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
            var userIds = await GetPosManagerUserIdsAsync(db, storeId, cancellationToken);
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
            var lowItems = items
                .Where(i => i.MinStock > 0 && i.OnHand <= i.MinStock)
                .Take(5)
                .ToList();
            if (lowItems.Count == 0) return;

            var userIds = await GetPosManagerUserIdsAsync(db, storeId, cancellationToken);
            if (userIds.Count == 0) return;

            var preview = string.Join(", ",
                lowItems.Select(i => $"{i.ProductName} ({i.OnHand:N0}/{i.MinStock:N0})"));
            var suffix = lowItems.Count >= 5 ? "…" : "";

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
            var userIds = await GetPosQrNotifyUserIdsAsync(db, storeId, cancellationToken);
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

    private static async Task<List<Guid>> GetPosQrNotifyUserIdsAsync(
        ZKTecoDbContext db,
        Guid storeId,
        CancellationToken cancellationToken)
    {
        var ids = new HashSet<Guid>(await GetPosManagerUserIdsAsync(db, storeId, cancellationToken));

        var ownerId = await db.Stores.AsNoTracking()
            .Where(s => s.Id == storeId)
            .Select(s => s.OwnerId)
            .FirstOrDefaultAsync(cancellationToken);
        if (ownerId is Guid oid && oid != Guid.Empty)
            ids.Add(oid);

        var rolesWithQr = await (
            from rp in db.RolePermissions.AsNoTracking()
            join p in db.Permissions.AsNoTracking() on rp.PermissionId equals p.Id
            where rp.IsActive && rp.CanView
                && (rp.StoreId == storeId || rp.StoreId == null)
                && p.Module == "PosQrOrder"
            select rp.RoleName
        ).Distinct().ToListAsync(cancellationToken);
        if (rolesWithQr.Count > 0)
        {
            var qrUsers = await db.Users.AsNoTracking()
                .Where(u => u.IsActive && u.StoreId == storeId && rolesWithQr.Contains(u.Role))
                .Select(u => u.Id)
                .ToListAsync(cancellationToken);
            foreach (var uid in qrUsers)
                ids.Add(uid);
        }

        return ids.ToList();
    }

    private static async Task<List<Guid>> GetPosManagerUserIdsAsync(
        ZKTecoDbContext db,
        Guid storeId,
        CancellationToken cancellationToken)
    {
        return await db.Users.AsNoTracking()
            .Where(u => u.StoreId == storeId &&
                        ManagerRoles.Contains(u.Role))
            .Select(u => u.Id)
            .Distinct()
            .ToListAsync(cancellationToken);
    }
}

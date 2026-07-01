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

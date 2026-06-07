using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Infrastructure.Services;

/// <summary>
/// Gửi thông báo khi tạo phiếu thu/chi tới: chủ cửa hàng, quản lý trực tiếp, người có quyền tạo.
/// </summary>
public static class CashTransactionNotificationHelper
{
    public static async Task NotifyOnCreatedAsync(
        ZKTecoDbContext context,
        IModulePermissionService permissionService,
        ISystemNotificationService notificationService,
        CashTransaction transaction,
        Guid creatorUserId,
        Guid storeId,
        CancellationToken cancellationToken = default)
    {
        var targets = await ResolveCreateNotifyTargetsAsync(
            context, permissionService, creatorUserId, storeId, cancellationToken);
        if (targets.Count == 0) return;

        var creator = await context.Users.AsNoTracking()
            .Where(u => u.Id == creatorUserId)
            .Select(u => new { u.FullName, u.UserName })
            .FirstOrDefaultAsync(cancellationToken);
        var creatorName = creator?.FullName ?? creator?.UserName ?? "Nhân viên";
        var typeLabel = transaction.Type == CashTransactionType.Income ? "Thu" : "Chi";

        await notificationService.CreateAndSendToUsersAsync(
            targets,
            NotificationType.Info,
            "Phiếu thu/chi mới",
            $"{creatorName} tạo phiếu {typeLabel} {transaction.TransactionCode}: {transaction.Amount:N0}đ — {transaction.Description}",
            relatedEntityId: transaction.Id,
            relatedEntityType: "CashTransaction",
            fromUserId: creatorUserId,
            categoryCode: "transaction",
            storeId: storeId);
    }

    internal static async Task<HashSet<Guid>> ResolveCreateNotifyTargetsAsync(
        ZKTecoDbContext context,
        IModulePermissionService permissionService,
        Guid creatorUserId,
        Guid storeId,
        CancellationToken cancellationToken = default)
    {
        var targets = new HashSet<Guid>();

        // 1. Chủ cửa hàng
        var ownerId = await context.Stores.AsNoTracking()
            .Where(s => s.Id == storeId)
            .Select(s => s.OwnerId)
            .FirstOrDefaultAsync(cancellationToken);
        if (ownerId.HasValue && ownerId.Value != Guid.Empty && ownerId.Value != creatorUserId)
            targets.Add(ownerId.Value);

        // 2. Quản lý trực tiếp của người tạo phiếu
        var directManagerUserId = await (
            from emp in context.Employees.AsNoTracking()
            join mgr in context.Employees.AsNoTracking()
                on emp.DirectManagerEmployeeId equals mgr.Id
            where emp.ApplicationUserId == creatorUserId
                  && emp.StoreId == storeId
                  && emp.Deleted == null
                  && mgr.ApplicationUserId != null
            select mgr.ApplicationUserId!.Value
        ).FirstOrDefaultAsync(cancellationToken);
        if (directManagerUserId != Guid.Empty && directManagerUserId != creatorUserId)
            targets.Add(directManagerUserId);

        // 3. Người có quyền tạo thu/chi trong cửa hàng
        var storeUsers = await context.Users.AsNoTracking()
            .Where(u => u.IsActive && u.StoreId == storeId && u.Id != creatorUserId)
            .Select(u => new { u.Id, u.Role })
            .ToListAsync(cancellationToken);

        foreach (var user in storeUsers)
        {
            if (await permissionService.HasPermissionAsync(
                    user.Id,
                    user.Role ?? string.Empty,
                    storeId,
                    "CashTransaction",
                    ModulePermissionAction.Create,
                    cancellationToken))
            {
                targets.Add(user.Id);
            }
        }

        return targets;
    }
}

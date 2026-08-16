using Microsoft.AspNetCore.Identity;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Gửi push/in-app tới tất cả SuperAdmin (cổng /admin).
/// </summary>
public static class SuperAdminNotificationHelper
{
    public const string AdminStoresUrl = "/admin/stores";
    public const string AdminDevicesUrl = "/admin/devices";
    public const string AdminLicensesUrl = "/admin/licenses";
    public const string AdminAgentsUrl = "/admin/agents";
    public const string AdminDashboardUrl = "/admin";

    public static async Task<IReadOnlyList<Guid>> GetSuperAdminUserIdsAsync(
        UserManager<ApplicationUser> userManager)
    {
        var users = await userManager.GetUsersInRoleAsync(nameof(Roles.SuperAdmin));
        return users.Where(u => u.IsActive).Select(u => u.Id).ToList();
    }

    public static async Task NotifySuperAdminsAsync(
        ISystemNotificationService notificationService,
        UserManager<ApplicationUser> userManager,
        NotificationType type,
        string title,
        string message,
        string? relatedUrl = null,
        Guid? relatedEntityId = null,
        string? relatedEntityType = null,
        string? categoryCode = null,
        Guid? storeId = null,
        IEnumerable<Guid>? excludeUserIds = null)
    {
        var exclude = excludeUserIds?.ToHashSet() ?? [];
        var ids = (await GetSuperAdminUserIdsAsync(userManager))
            .Where(id => !exclude.Contains(id))
            .ToList();
        if (ids.Count == 0) return;

        await notificationService.CreateAndSendToUsersAsync(
            targetUserIds: ids,
            type: type,
            title: title,
            message: message,
            relatedUrl: relatedUrl,
            relatedEntityId: relatedEntityId,
            relatedEntityType: relatedEntityType,
            categoryCode: categoryCode,
            storeId: storeId);
    }
}

using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Services;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// ExecuteUpdate cho gán cửa hàng / license đại lý — tránh EF change-tracker không flush FK.
/// </summary>
internal static class AgentAssignmentPersistHelper
{
    public const string LicenseAlreadyAssignedMessage =
        "Key đã được cấp cho đại lý khác. Thu hồi key đó rồi cấp key khác cho đại lý này.";

    public static Task<(bool Ok, string? Error)> AssignStoreToAgentAsync(
        ZKTecoDbContext db, Guid storeId, Guid agentId, string updatedBy) =>
        new StoreAgentLinkService(db).LinkStoreToAgentAsync(storeId, agentId, updatedBy);

    public static Task<(bool Ok, string? Error)> RemoveStoreFromAgentAsync(
        ZKTecoDbContext db, Guid storeId, Guid agentId, string updatedBy) =>
        new StoreAgentLinkService(db).UnlinkStoreFromAgentAsync(storeId, agentId, updatedBy);

    public static async Task<(bool Ok, string? Error)> AssignLicenseToAgentAsync(
        ZKTecoDbContext db, Guid licenseId, Guid agentId, string updatedBy)
    {
        var now = DateTime.UtcNow;
        var updated = await db.LicenseKeys
            // Không lấy key đang thuộc đại lý khác (trước đây chuyển lặng lẽ, đại lý cũ mất key).
            .Where(l => l.Id == licenseId && !l.IsUsed && l.IsActive
                        && (l.AgentId == null || l.AgentId == agentId))
            .ExecuteUpdateAsync(s => s
                .SetProperty(l => l.AgentId, agentId)
                .SetProperty(l => l.UpdatedAt, now)
                .SetProperty(l => l.UpdatedBy, updatedBy));

        if (updated > 0) return (true, null);

        var row = await db.LicenseKeys.AsNoTracking()
            .Where(l => l.Id == licenseId)
            .Select(l => new { l.AgentId, l.IsUsed, l.IsActive })
            .FirstOrDefaultAsync();
        if (row == null) return (false, "Không tìm thấy license key");
        if (row.IsUsed) return (false, "License key đã được sử dụng");
        if (!row.IsActive) return (false, "License key đã bị thu hồi");
        if (row.AgentId == agentId) return (true, null);
        return (false, LicenseAlreadyAssignedMessage);
    }

    public static async Task<int> BatchAssignLicensesToAgentAsync(
        ZKTecoDbContext db, IEnumerable<Guid> licenseIds, Guid agentId, string updatedBy)
    {
        var now = DateTime.UtcNow;
        var idList = licenseIds.ToList();
        if (idList.Count == 0) return 0;

        return await db.LicenseKeys
            .Where(l => idList.Contains(l.Id) && !l.IsUsed && l.IsActive
                        && (l.AgentId == null || l.AgentId == agentId))
            .ExecuteUpdateAsync(s => s
                .SetProperty(l => l.AgentId, agentId)
                .SetProperty(l => l.UpdatedAt, now)
                .SetProperty(l => l.UpdatedBy, updatedBy));
    }
}

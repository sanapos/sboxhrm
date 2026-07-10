using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Services;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// ExecuteUpdate cho gán cửa hàng / license đại lý — tránh EF change-tracker không flush FK.
/// </summary>
internal static class AgentAssignmentPersistHelper
{
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
            .Where(l => l.Id == licenseId && !l.IsUsed && l.IsActive)
            .ExecuteUpdateAsync(s => s
                .SetProperty(l => l.AgentId, agentId)
                .SetProperty(l => l.UpdatedAt, now)
                .SetProperty(l => l.UpdatedBy, updatedBy));

        if (updated > 0) return (true, null);

        var already = await db.LicenseKeys.AsNoTracking()
            .AnyAsync(l => l.Id == licenseId && l.AgentId == agentId && !l.IsUsed);
        return already
            ? (true, null)
            : (false, "Không gán được license cho đại lý — key đã dùng hoặc không tồn tại");
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

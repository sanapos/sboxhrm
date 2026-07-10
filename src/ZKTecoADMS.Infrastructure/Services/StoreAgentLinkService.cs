using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.Interfaces;

namespace ZKTecoADMS.Infrastructure.Services;

public class StoreAgentLinkService(ZKTecoDbContext db) : IStoreAgentLinkService
{
    public async Task<(bool Ok, string? Error)> LinkStoreToAgentAsync(
        Guid storeId,
        Guid agentId,
        string updatedBy,
        CancellationToken cancellationToken = default)
    {
        var now = DateTime.UtcNow;
        var updated = await db.Stores
            .Where(s => s.Id == storeId && s.AgentId != agentId)
            .ExecuteUpdateAsync(s => s
                .SetProperty(x => x.AgentId, agentId)
                .SetProperty(x => x.UpdatedAt, now)
                .SetProperty(x => x.UpdatedBy, updatedBy), cancellationToken);

        if (updated > 0) return (true, null);

        var already = await db.Stores.AsNoTracking()
            .AnyAsync(s => s.Id == storeId && s.AgentId == agentId, cancellationToken);
        return already
            ? (true, null)
            : (false, "Không gán được cửa hàng cho đại lý — vui lòng thử lại");
    }

    public async Task<(bool Ok, string? Error)> UnlinkStoreFromAgentAsync(
        Guid storeId,
        Guid agentId,
        string updatedBy,
        CancellationToken cancellationToken = default)
    {
        var now = DateTime.UtcNow;
        var updated = await db.Stores
            .Where(s => s.Id == storeId && s.AgentId == agentId)
            .ExecuteUpdateAsync(s => s
                .SetProperty(x => x.AgentId, (Guid?)null)
                .SetProperty(x => x.UpdatedAt, now)
                .SetProperty(x => x.UpdatedBy, updatedBy), cancellationToken);

        if (updated > 0) return (true, null);

        var already = await db.Stores.AsNoTracking()
            .AnyAsync(s => s.Id == storeId && s.AgentId == null, cancellationToken);
        return already
            ? (true, null)
            : (false, "Cửa hàng không thuộc đại lý này hoặc không gỡ được — vui lòng tải lại");
    }
}

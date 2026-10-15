using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Application.Helpers;

/// <summary>
/// Quy tắc kích hoạt license key cho cửa hàng:
/// - Key chưa gán đại lý (AgentId null) → dùng được mọi cửa hàng.
/// - Key đã gán đại lý → chỉ cửa hàng thuộc đúng đại lý đó.
/// </summary>
public static class LicenseKeyActivationHelper
{
    public const string InvalidScopeMessage =
        "License key không thuộc đại lý của cửa hàng này hoặc đã được cấp cho đại lý khác.";

    public static bool CanActivateForStore(LicenseKey license, Store store)
    {
        if (!license.IsActive || license.IsUsed)
            return false;

        if (license.AgentId == null)
            return true;

        return store.AgentId.HasValue && license.AgentId.Value == store.AgentId.Value;
    }

    /// <param name="actingAgentId">Đại lý đang xem: chỉ key đã cấp cho đại lý đó (không lộ kho key chưa cấp).</param>
    public static IQueryable<LicenseKey> FilterActivatableForStore(
        IQueryable<LicenseKey> query,
        Store store,
        Guid? actingAgentId = null)
    {
        if (actingAgentId.HasValue)
        {
            var agentId = actingAgentId.Value;
            return query.Where(l => l.IsActive && !l.IsUsed && l.AgentId == agentId
                                    && store.AgentId == agentId);
        }

        return query.Where(l =>
            l.IsActive &&
            !l.IsUsed &&
            (l.AgentId == null || (store.AgentId != null && l.AgentId == store.AgentId)));
    }
}

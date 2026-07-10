namespace ZKTecoADMS.Application.Interfaces;

/// <summary>
/// Gán / gỡ cửa hàng cho đại lý qua ExecuteUpdate (tránh EF change-tracker không flush FK).
/// </summary>
public interface IStoreAgentLinkService
{
    Task<(bool Ok, string? Error)> LinkStoreToAgentAsync(
        Guid storeId,
        Guid agentId,
        string updatedBy,
        CancellationToken cancellationToken = default);

    Task<(bool Ok, string? Error)> UnlinkStoreFromAgentAsync(
        Guid storeId,
        Guid agentId,
        string updatedBy,
        CancellationToken cancellationToken = default);
}

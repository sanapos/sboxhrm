namespace ZKTecoADMS.Application.Interfaces;

public interface IStoreLicenseLimitService
{
    Task<(bool Ok, string? Error)> CanAddUserAsync(Guid storeId, CancellationToken cancellationToken = default);
    Task<(bool Ok, string? Error)> CanAddDeviceAsync(Guid storeId, CancellationToken cancellationToken = default);
    Task<(bool Ok, string? Error)> CanAddBranchAsync(Guid storeId, CancellationToken cancellationToken = default);
    Task<(bool Ok, string? Error)> EnsureAccessAllowedAsync(
        Guid storeId,
        Guid userId,
        string? platform,
        string? deviceKey,
        string? deviceName,
        CancellationToken cancellationToken = default);
    Task<bool> CanSendFcmAsync(Guid storeId, string? categoryCode, CancellationToken cancellationToken = default);
}

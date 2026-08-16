using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Infrastructure.Helpers;

namespace ZKTecoADMS.Infrastructure.Services;

public class StoreLicenseLimitService(ZKTecoDbContext db) : IStoreLicenseLimitService
{
    public Task<(bool Ok, string? Error)> CanAddUserAsync(
        Guid storeId,
        CancellationToken cancellationToken = default) =>
        StorePackageHelper.CanAddUserAsync(db, storeId, cancellationToken);

    public Task<(bool Ok, string? Error)> CanAddDeviceAsync(
        Guid storeId,
        CancellationToken cancellationToken = default) =>
        StorePackageHelper.CanAddDeviceAsync(db, storeId, cancellationToken);

    public Task<(bool Ok, string? Error)> CanAddBranchAsync(
        Guid storeId,
        CancellationToken cancellationToken = default) =>
        StorePackageHelper.CanAddBranchAsync(db, storeId, cancellationToken);

    public Task<(bool Ok, string? Error)> EnsureAccessAllowedAsync(
        Guid storeId,
        Guid userId,
        string? platform,
        string? deviceKey,
        string? deviceName,
        CancellationToken cancellationToken = default) =>
        StorePackageHelper.EnsureAccessAllowedAsync(
            db, storeId, userId, platform, deviceKey, deviceName, cancellationToken);

    public Task<bool> CanSendFcmAsync(
        Guid storeId,
        string? categoryCode,
        CancellationToken cancellationToken = default) =>
        StorePackageHelper.CanSendFcmAsync(db, storeId, categoryCode, cancellationToken);
}

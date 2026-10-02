using Microsoft.EntityFrameworkCore;
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

    public async Task<bool> IsAccessDeviceReleasedAsync(
        Guid storeId,
        string? deviceKey,
        CancellationToken cancellationToken = default)
    {
        var key = (deviceKey ?? "").Trim();
        if (key.Length == 0) return false;
        if (key.Length > 80) key = key[..80];
        return await db.StoreAccessDevices.IgnoreQueryFilters().AsNoTracking()
            .AnyAsync(d => d.StoreId == storeId && d.DeviceKey == key && (d.Deleted != null || !d.IsActive), cancellationToken);
    }

    public Task<bool> CanSendFcmAsync(
        Guid storeId,
        string? categoryCode,
        CancellationToken cancellationToken = default) =>
        StorePackageHelper.CanSendFcmAsync(db, storeId, categoryCode, cancellationToken);
}

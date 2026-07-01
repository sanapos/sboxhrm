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
}

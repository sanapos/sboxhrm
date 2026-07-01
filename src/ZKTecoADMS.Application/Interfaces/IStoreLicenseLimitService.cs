namespace ZKTecoADMS.Application.Interfaces;

public interface IStoreLicenseLimitService
{
    Task<(bool Ok, string? Error)> CanAddUserAsync(Guid storeId, CancellationToken cancellationToken = default);
    Task<(bool Ok, string? Error)> CanAddDeviceAsync(Guid storeId, CancellationToken cancellationToken = default);
}

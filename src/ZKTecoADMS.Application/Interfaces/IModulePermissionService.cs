using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.DTOs.Permissions;

namespace ZKTecoADMS.Application.Interfaces;

public interface IModulePermissionService
{
    Task<IReadOnlyDictionary<string, ModulePermissionDto>> GetEffectivePermissionsAsync(
        Guid userId,
        string role,
        Guid? storeId,
        CancellationToken cancellationToken = default);

    Task<bool> HasPermissionAsync(
        Guid userId,
        string role,
        Guid? storeId,
        string module,
        ModulePermissionAction action,
        CancellationToken cancellationToken = default);
}

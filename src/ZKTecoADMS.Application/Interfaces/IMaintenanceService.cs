using ZKTecoADMS.Application.DTOs.SystemAdmin;

namespace ZKTecoADMS.Application.Interfaces;

public interface IMaintenanceService
{
    Task<List<MaintenanceWindowDto>> ListAsync(bool? activeOnly, CancellationToken ct = default);
    Task<MaintenanceWindowDto> CreateAsync(CreateMaintenanceWindowDto dto, Guid userId, CancellationToken ct = default);
    Task<bool> SetActiveAsync(Guid id, bool active, CancellationToken ct = default);
    Task<bool> DeleteAsync(Guid id, CancellationToken ct = default);

    /// <summary>Lấy maintenance đang hiệu lực (now ∈ [Start,End], IsActive=true). null nếu không có.</summary>
    Task<ActiveMaintenanceDto> GetActiveAsync(CancellationToken ct = default);
}

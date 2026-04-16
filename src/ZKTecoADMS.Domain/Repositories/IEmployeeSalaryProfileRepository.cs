using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Domain.Repositories;

public interface IEmployeeSalaryProfileRepository : IRepository<EmployeeBenefit>
{
    Task<EmployeeBenefit?> GetActiveByEmployeeIdAsync(Guid employeeId, CancellationToken cancellationToken = default);
    Task<List<EmployeeBenefit>> GetByEmployeeIdAsync(Guid employeeId, CancellationToken cancellationToken = default);
    Task<EmployeeBenefit?> GetByIdWithDetailsAsync(Guid id, CancellationToken cancellationToken = default);
    Task DeactivateOtherProfilesAsync(Guid employeeId, Guid currentProfileId, CancellationToken cancellationToken = default);
}

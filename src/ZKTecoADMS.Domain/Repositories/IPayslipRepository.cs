using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Domain.Repositories;

public interface IPayslipRepository
{
    Task<Payslip?> GetByIdAsync(Guid storeId, Guid id, CancellationToken cancellationToken = default);
    Task<List<Payslip>> GetAllAsync(Guid storeId, CancellationToken cancellationToken = default);
    Task<List<Payslip>> GetByEmployeeUserIdAsync(Guid storeId, Guid employeeUserId, CancellationToken cancellationToken = default);
    Task<Payslip?> GetByEmployeeUserAndPeriodAsync(Guid storeId, Guid employeeUserId, int year, int month, CancellationToken cancellationToken = default);
    Task<List<Payslip>> GetByPeriodAsync(Guid storeId, int year, int month, CancellationToken cancellationToken = default);
    Task<Payslip> CreateAsync(Payslip payslip, CancellationToken cancellationToken = default);
    Task<Payslip> UpdateAsync(Payslip payslip, CancellationToken cancellationToken = default);
    Task DeleteAsync(Guid storeId, Guid id, CancellationToken cancellationToken = default);
    Task<bool> ExistsForEmployeeUserAndPeriodAsync(Guid storeId, Guid employeeUserId, int year, int month, CancellationToken cancellationToken = default);
    Task<List<Payslip>> GetPayslipsByManagerIdAsync(Guid storeId, Guid managerId, int year, int month, CancellationToken cancellationToken = default);
}

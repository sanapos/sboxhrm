using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Infrastructure.Repositories;

public class PayslipRepository(ZKTecoDbContext context) : IPayslipRepository
{
    public async Task<Payslip?> GetByIdAsync(Guid storeId, Guid id, CancellationToken cancellationToken = default)
    {
        return await context.Payslips
            .Include(p => p.EmployeeUser)
            .Include(p => p.SalaryProfile)
            .Include(p => p.GeneratedByUser)
            .Include(p => p.ApprovedByUser)
            .FirstOrDefaultAsync(p => p.Id == id && p.StoreId == storeId, cancellationToken);
    }

    public async Task<List<Payslip>> GetAllAsync(Guid storeId, CancellationToken cancellationToken = default)
    {
        return await context.Payslips
            .Include(p => p.EmployeeUser)
            .Include(p => p.SalaryProfile)
            .Include(p => p.GeneratedByUser)
            .Where(p => p.StoreId == storeId)
            .OrderByDescending(p => p.Year)
            .ThenByDescending(p => p.Month)
            .ThenBy(p => p.EmployeeUser.UserName)
            .ToListAsync(cancellationToken);
    }

    public async Task<List<Payslip>> GetByEmployeeUserIdAsync(Guid storeId, Guid employeeUserId, CancellationToken cancellationToken = default)
    {
        return await context.Payslips
            .Include(p => p.SalaryProfile)
            .Include(p => p.GeneratedByUser)
            .Include(p => p.ApprovedByUser)
            .Where(p => p.EmployeeUserId == employeeUserId && p.StoreId == storeId)
            .OrderByDescending(p => p.Year)
            .ThenByDescending(p => p.Month)
            .ToListAsync(cancellationToken);
    }

    public async Task<Payslip?> GetByEmployeeUserAndPeriodAsync(Guid storeId, Guid employeeUserId, int year, int month, CancellationToken cancellationToken = default)
    {
        return await context.Payslips
            .Include(p => p.EmployeeUser)
            .Include(p => p.SalaryProfile)
            .Include(p => p.GeneratedByUser)
            .Include(p => p.ApprovedByUser)
            .FirstOrDefaultAsync(p => p.EmployeeUserId == employeeUserId && p.Year == year && p.Month == month && p.StoreId == storeId, cancellationToken);
    }

    public async Task<List<Payslip>> GetByPeriodAsync(Guid storeId, int year, int month, CancellationToken cancellationToken = default)
    {
        return await context.Payslips
            .Include(p => p.EmployeeUser)
            .Include(p => p.SalaryProfile)
            .Where(p => p.Year == year && p.Month == month && p.StoreId == storeId)
            .OrderBy(p => p.EmployeeUser.UserName)
            .ToListAsync(cancellationToken);
    }

    public async Task<Payslip> CreateAsync(Payslip payslip, CancellationToken cancellationToken = default)
    {
        context.Payslips.Add(payslip);
        await context.SaveChangesAsync(cancellationToken);
        return payslip;
    }

    public async Task<Payslip> UpdateAsync(Payslip payslip, CancellationToken cancellationToken = default)
    {
        context.Payslips.Update(payslip);
        await context.SaveChangesAsync(cancellationToken);
        return payslip;
    }

    public async Task DeleteAsync(Guid storeId, Guid id, CancellationToken cancellationToken = default)
    {
        var payslip = await context.Payslips.FirstOrDefaultAsync(p => p.Id == id && p.StoreId == storeId, cancellationToken);
        if (payslip != null)
        {
            context.Payslips.Remove(payslip);
            await context.SaveChangesAsync(cancellationToken);
        }
    }

    public async Task<bool> ExistsForEmployeeUserAndPeriodAsync(Guid storeId, Guid employeeUserId, int year, int month, CancellationToken cancellationToken = default)
    {
        return await context.Payslips
            .AnyAsync(p => p.EmployeeUserId == employeeUserId && p.Year == year && p.Month == month && p.StoreId == storeId, cancellationToken);
    }

    public async Task<List<Payslip>> GetPayslipsByManagerIdAsync(Guid storeId, Guid managerId, int year, int month, CancellationToken cancellationToken = default) {
        return await context.Payslips
            .Include(p => p.EmployeeUser)
            .Include(p => p.SalaryProfile)
            .Where(p => p.EmployeeUser.ManagerId == managerId && p.Year == year && p.Month == month && p.StoreId == storeId)
            .OrderBy(p => p.EmployeeUser.UserName)
            .ToListAsync(cancellationToken);
    }
}

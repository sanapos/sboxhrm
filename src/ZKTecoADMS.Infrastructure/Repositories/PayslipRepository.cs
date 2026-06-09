using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Infrastructure.Repositories;

public class PayslipRepository(ZKTecoDbContext context) : IPayslipRepository
{
    public async Task<Payslip?> GetByIdAsync(Guid storeId, Guid id, CancellationToken cancellationToken = default)
    {
        return await context.Payslips
            .Include(p => p.Employee)
            .Include(p => p.EmployeeUser)
            .Include(p => p.SalaryProfile)
            .Include(p => p.GeneratedByUser)
            .Include(p => p.ApprovedByUser)
            .FirstOrDefaultAsync(p => p.Id == id && p.StoreId == storeId, cancellationToken);
    }

    public async Task<List<Payslip>> GetAllAsync(Guid storeId, CancellationToken cancellationToken = default)
    {
        return await context.Payslips
            .Include(p => p.Employee)
            .Include(p => p.EmployeeUser)
            .Include(p => p.SalaryProfile)
            .Include(p => p.GeneratedByUser)
            .Where(p => p.StoreId == storeId)
            .OrderByDescending(p => p.Year)
            .ThenByDescending(p => p.Month)
            .ThenBy(p => p.Employee.EmployeeCode)
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
            .Include(p => p.Employee)
            .Include(p => p.EmployeeUser)
            .Include(p => p.SalaryProfile)
            .Include(p => p.GeneratedByUser)
            .Include(p => p.ApprovedByUser)
            .FirstOrDefaultAsync(
                p => p.EmployeeUserId == employeeUserId &&
                     p.Year == year &&
                     p.Month == month,
                cancellationToken);
    }

    public async Task<Payslip?> GetByEmployeeAndPeriodAsync(Guid storeId, Guid employeeId, int year, int month, CancellationToken cancellationToken = default)
    {
        return await context.Payslips
            .Include(p => p.Employee)
            .Include(p => p.EmployeeUser)
            .Include(p => p.SalaryProfile)
            .Include(p => p.GeneratedByUser)
            .Include(p => p.ApprovedByUser)
            // Unique index is (EmployeeId, Year, Month) — lookup without StoreId
            // so re-chốt always updates instead of hitting duplicate key.
            .FirstOrDefaultAsync(
                p => p.EmployeeId == employeeId &&
                     p.Year == year &&
                     p.Month == month,
                cancellationToken);
    }

    public async Task<List<Payslip>> GetByPeriodAsync(Guid storeId, int year, int month, CancellationToken cancellationToken = default)
    {
        return await context.Payslips
            .Include(p => p.Employee)
            .Include(p => p.EmployeeUser)
            .Include(p => p.SalaryProfile)
            .Where(p => p.Year == year && p.Month == month && p.StoreId == storeId)
            .OrderBy(p => p.Employee.EmployeeCode)
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
            .Include(p => p.Employee)
            .Include(p => p.EmployeeUser)
            .Include(p => p.SalaryProfile)
            .Where(p => p.EmployeeUser != null &&
                        p.EmployeeUser.ManagerId == managerId &&
                        p.Year == year &&
                        p.Month == month &&
                        p.StoreId == storeId)
            .OrderBy(p => p.Employee.EmployeeCode)
            .ToListAsync(cancellationToken);
    }

    public async Task<List<Payslip>> GetByStoreAndPeriodAsync(Guid storeId, int year, int? month, CancellationToken cancellationToken = default)
    {
        var q = context.Payslips
            .Include(p => p.Employee)
            .Include(p => p.EmployeeUser)
            .Include(p => p.SalaryProfile)
            .Where(p => p.StoreId == storeId && p.Year == year);
        if (month.HasValue)
        {
            q = q.Where(p => p.Month == month.Value);
        }
        return await q
            .OrderByDescending(p => p.Month)
            .ThenBy(p => p.Employee.EmployeeCode)
            .ToListAsync(cancellationToken);
    }

    public async Task<List<Payslip>> SearchAsync(
        Guid storeId,
        int? year,
        int? month,
        Guid? employeeUserId,
        string? department,
        DateTime? periodStartFrom,
        DateTime? periodEndTo,
        CancellationToken cancellationToken = default)
    {
        var q = context.Payslips
            .Include(p => p.Employee)
            .Include(p => p.EmployeeUser)
            .Include(p => p.SalaryProfile)
            .Include(p => p.GeneratedByUser)
            .Include(p => p.ApprovedByUser)
            .Where(p =>
                p.StoreId == storeId ||
                (p.StoreId == null && context.Employees.Any(e =>
                    e.Id == p.EmployeeId &&
                    e.StoreId == storeId)));

        if (year.HasValue)
            q = q.Where(p => p.Year == year.Value);
        if (month.HasValue)
            q = q.Where(p => p.Month == month.Value);
        if (employeeUserId.HasValue)
        {
            q = q.Where(p =>
                p.EmployeeUserId == employeeUserId.Value ||
                context.Employees.Any(e =>
                    e.Id == p.EmployeeId &&
                    e.ApplicationUserId == employeeUserId.Value));
        }
        if (periodStartFrom.HasValue)
            q = q.Where(p => p.PeriodEnd >= periodStartFrom.Value);
        if (periodEndTo.HasValue)
            q = q.Where(p => p.PeriodStart <= periodEndTo.Value);
        if (!string.IsNullOrWhiteSpace(department))
        {
            q = q.Where(p => context.Employees.Any(e =>
                e.Id == p.EmployeeId &&
                e.StoreId == storeId &&
                e.Department == department));
        }

        return await q
            .OrderByDescending(p => p.Year)
            .ThenByDescending(p => p.Month)
            .ThenBy(p => p.Employee.EmployeeCode)
            .ToListAsync(cancellationToken);
    }
}

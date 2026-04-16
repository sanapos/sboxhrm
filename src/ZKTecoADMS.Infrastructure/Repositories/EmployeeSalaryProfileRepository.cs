using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Infrastructure.Repositories;

public class EmployeeSalaryProfileRepository : EfRepository<EmployeeBenefit>, IEmployeeSalaryProfileRepository
{
    private readonly ZKTecoDbContext _context;

    public EmployeeSalaryProfileRepository(ZKTecoDbContext context, ILogger<EfRepository<EmployeeBenefit>> logger, ITenantProvider tenantProvider) 
        : base(context, logger, tenantProvider)
    {
        _context = context;
    }

    public async Task<EmployeeBenefit?> GetActiveByEmployeeIdAsync(Guid employeeId, CancellationToken cancellationToken = default)
    {
        return await _context.Set<EmployeeBenefit>()
            .Include(x => x.Employee)
            .Where(x => x.EmployeeId == employeeId && x.IsActive)
            .OrderByDescending(x => x.EffectiveDate)
            .FirstOrDefaultAsync(cancellationToken);
    }

    public async Task<List<EmployeeBenefit>> GetByEmployeeIdAsync(Guid employeeId, CancellationToken cancellationToken = default)
    {
        return await _context.Set<EmployeeBenefit>()
            .Where(x => x.EmployeeId == employeeId)
            .OrderByDescending(x => x.EffectiveDate)
            .ToListAsync(cancellationToken);
    }

    public async Task<EmployeeBenefit?> GetByIdWithDetailsAsync(Guid id, CancellationToken cancellationToken = default)
    {
        return await _context.Set<EmployeeBenefit>()
            .Include(x => x.Employee)
            .FirstOrDefaultAsync(x => x.Id == id, cancellationToken);
    }

    public async Task DeactivateOtherProfilesAsync(Guid employeeId, Guid currentProfileId, CancellationToken cancellationToken = default)
    {
        var otherProfiles = await _context.Set<EmployeeBenefit>()
            .Where(x => x.EmployeeId == employeeId && x.Id != currentProfileId && x.IsActive)
            .ToListAsync(cancellationToken);

        foreach (var profile in otherProfiles)
        {
            profile.IsActive = false;
            profile.EndDate = DateTime.Now;
        }

        await _context.SaveChangesAsync(cancellationToken);
    }
}

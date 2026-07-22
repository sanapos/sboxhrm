using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.DTOs.Commons;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Application.Queries.Users.GetStoreAccounts;

public class GetStoreAccountsHandler(
    UserManager<ApplicationUser> userManager,
    IRepository<Store> storeRepository,
    DbContext dbContext
) : IQueryHandler<GetStoreAccountsQuery, AppResponse<IEnumerable<AccountDto>>>
{
    public async Task<AppResponse<IEnumerable<AccountDto>>> Handle(
        GetStoreAccountsQuery request,
        CancellationToken cancellationToken)
    {
        // Get store to find owner
        var store = await storeRepository.GetByIdAsync(request.StoreId);
        var ownerId = store?.OwnerId;

        var accounts = await userManager.Users
            .Where(u => u.StoreId == request.StoreId)
            .Include(u => u.Employee)
            .Include(u => u.Manager)
            .OrderByDescending(u => u.CreatedAt)
            .Select(u => new AccountDto
            {
                Id = u.Id,
                Email = u.Email ?? string.Empty,
                UserName = u.UserName ?? string.Empty,
                FirstName = u.FirstName,
                LastName = u.LastName,
                PhoneNumber = u.PhoneNumber,
                Roles = u.Role != null ? new List<string> { u.Role } : new List<string>(),
                ManagerId = u.ManagerId,
                ManagerName = u.Manager != null ? (u.Manager.LastName + " " + u.Manager.FirstName) : null,
                EmployeeId = u.Employee != null ? u.Employee.Id : (Guid?)null,
                EmployeeWorkStatus = u.Employee != null ? u.Employee.WorkStatus.ToString() : null,
                CreatedAt = u.CreatedAt,
                IsActive = u.IsActive,
                LastLoginAt = u.LastLoginAt,
                IsOwner = ownerId != null && u.Id == ownerId
            })
            .ToListAsync(cancellationToken);

        if (accounts.Count == 0)
            return AppResponse<IEnumerable<AccountDto>>.Success(accounts);

        var userIds = accounts.Select(a => a.Id).ToList();

        // Include soft-deleted employees so we can flag accounts whose HR profile was removed.
        var hrLinks = await dbContext.Set<Employee>()
            .IgnoreQueryFilters()
            .AsNoTracking()
            .Where(e =>
                e.StoreId == request.StoreId
                && e.ApplicationUserId != null
                && userIds.Contains(e.ApplicationUserId.Value))
            .Select(e => new
            {
                UserId = e.ApplicationUserId!.Value,
                e.Id,
                e.WorkStatus,
                e.Deleted
            })
            .ToListAsync(cancellationToken);

        var linksByUser = hrLinks
            .GroupBy(x => x.UserId)
            .ToDictionary(g => g.Key, g => g.ToList());

        foreach (var account in accounts)
        {
            // Store owner often has no HR profile — exclude from this cleanup filter.
            if (account.IsOwner)
                continue;

            if (!linksByUser.TryGetValue(account.Id, out var links))
            {
                // Login exists but never linked to any Employee row (common after HR delete
                // that cleared ApplicationUserId, or account created without HS).
                account.EmployeeId = null;
                account.EmployeeWorkStatus = null;
                account.IsEmployeeMissing = true;
                account.IsEmployeeMissingOrResigned = true;
                continue;
            }

            var activeLink = links.FirstOrDefault(l => l.Deleted == null);
            if (activeLink == null)
            {
                account.EmployeeId = null;
                account.EmployeeWorkStatus = null;
                account.IsEmployeeMissing = true;
                account.IsEmployeeMissingOrResigned = true;
                continue;
            }

            account.EmployeeId = activeLink.Id;
            account.EmployeeWorkStatus = activeLink.WorkStatus.ToString();
            if (activeLink.WorkStatus == EmployeeWorkStatus.Resigned)
            {
                account.IsEmployeeResigned = true;
                account.IsEmployeeMissingOrResigned = true;
            }
        }

        return AppResponse<IEnumerable<AccountDto>>.Success(accounts);
    }
}

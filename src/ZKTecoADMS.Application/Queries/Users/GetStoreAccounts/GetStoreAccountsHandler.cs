using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.DTOs.Commons;

namespace ZKTecoADMS.Application.Queries.Users.GetStoreAccounts;

public class GetStoreAccountsHandler(
    UserManager<ApplicationUser> userManager,
    IRepository<Store> storeRepository
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
                CreatedAt = u.CreatedAt,
                IsActive = u.IsActive,
                LastLoginAt = u.LastLoginAt,
                IsOwner = ownerId != null && u.Id == ownerId
            })
            .ToListAsync(cancellationToken);

        return AppResponse<IEnumerable<AccountDto>>.Success(accounts);
    }
}

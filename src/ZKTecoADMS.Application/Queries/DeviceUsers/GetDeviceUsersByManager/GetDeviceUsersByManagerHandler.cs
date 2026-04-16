using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.DTOs.Commons;

namespace ZKTecoADMS.Application.Queries.DeviceUsers.GetDeviceUsersByManager;

public class GetDeviceUsersByManagerHandler(
    UserManager<ApplicationUser> userManager
) : IQueryHandler<GetDeviceUsersByManagerQuery, AppResponse<IEnumerable<AccountDto>>>
{
    public async Task<AppResponse<IEnumerable<AccountDto>>> Handle(
        GetDeviceUsersByManagerQuery request,
        CancellationToken cancellationToken)
    {
        var accountDtos = await userManager.Users
            .Where(u => request.SubordinateUserIds == null || request.SubordinateUserIds.Contains(u.Id))
            .Include(u => u.Employee)
            .Select(u => new AccountDto
            {
                Id = u.Id,
                FirstName = u.FirstName!,
                LastName = u.LastName!,
                Email = u.Email!,
                PhoneNumber = u.PhoneNumber
            })
            .ToListAsync(cancellationToken: cancellationToken);
        // Get all users managed by this manager

        return AppResponse<IEnumerable<AccountDto>>.Success(accountDtos);
    }
}

using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.CQRS;
using ZKTecoADMS.Application.DTOs.Users;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Application.Queries.Users.GetCurrentUserProfile;

public class GetCurrentUserProfileHandler(UserManager<ApplicationUser> userManager) 
    : IQueryHandler<GetCurrentUserProfileQuery, AppResponse<UserProfileDto>>
{
    public async Task<AppResponse<UserProfileDto>> Handle(GetCurrentUserProfileQuery request, CancellationToken cancellationToken)
    {
        var user = await userManager.Users
            .Include(u => u.Manager)
            .FirstOrDefaultAsync(u => u.Id == request.UserId, cancellationToken);

        if (user == null)
        {
            return AppResponse<UserProfileDto>.Error("User not found");
        }

        var roles = await userManager.GetRolesAsync(user);

        var profile = new UserProfileDto
        {
            Id = user.Id,
            Email = user.Email ?? string.Empty,
            UserName = user.UserName ?? string.Empty,
            FirstName = user.FirstName,
            LastName = user.LastName,
            PhoneNumber = user.PhoneNumber,
            Roles = roles.ToList(),
            ManagerId = user.ManagerId,
            ManagerName = user.Manager != null ? $"{user.Manager.LastName} {user.Manager.FirstName}" : null,
            Created = user.CreatedAt
        };

        return AppResponse<UserProfileDto>.Success(profile);
    }
}

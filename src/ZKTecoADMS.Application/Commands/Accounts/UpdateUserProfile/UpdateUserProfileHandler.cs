using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.DTOs.Users;

namespace ZKTecoADMS.Application.Commands.Accounts.UpdateUserProfile;

public class UpdateUserProfileHandler(UserManager<ApplicationUser> userManager) 
    : ICommandHandler<UpdateUserProfileCommand, AppResponse<UserProfileDto>>
{
    public async Task<AppResponse<UserProfileDto>> Handle(UpdateUserProfileCommand request, CancellationToken cancellationToken)
    {
        var user = await userManager.Users
            .Include(u => u.Manager)
            .FirstOrDefaultAsync(u => u.Id == request.UserId, cancellationToken);

        if (user == null)
        {
            return AppResponse<UserProfileDto>.Error("User not found");
        }

        // Update basic profile information
        user.FirstName = request.FirstName;
        user.LastName = request.LastName;
        user.PhoneNumber = request.PhoneNumber;

        var updateResult = await userManager.UpdateAsync(user);
        if (!updateResult.Succeeded)
        {
            var errors = string.Join(", ", updateResult.Errors.Select(e => e.Description));
            return AppResponse<UserProfileDto>.Error($"Failed to update profile: {errors}");
        }

        // Refresh user data
        user = await userManager.Users
            .Include(u => u.Manager)
            .FirstOrDefaultAsync(u => u.Id == request.UserId, cancellationToken);

        var roles = await userManager.GetRolesAsync(user!);

        var profile = new UserProfileDto
        {
            Id = user!.Id,
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

using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.DTOs.Users;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.Accounts.UpdateUserPassword;

public class UpdateUserPasswordHandler(
    UserManager<ApplicationUser> userManager,
    ISystemNotificationService notificationService) 
    : ICommandHandler<UpdateUserPasswordCommand, AppResponse<UserProfileDto>>
{
    public async Task<AppResponse<UserProfileDto>> Handle(UpdateUserPasswordCommand request, CancellationToken cancellationToken)
    {
        var user = await userManager.Users
            .Include(u => u.Manager)
            .FirstOrDefaultAsync(u => u.Id == request.UserId, cancellationToken);

        if (user == null)
        {
            return AppResponse<UserProfileDto>.Error("User not found");
        }

        // Change password
        var passwordResult = await userManager.ChangePasswordAsync(user, request.CurrentPassword, request.NewPassword);
        if (!passwordResult.Succeeded)
        {
            var errors = string.Join(", ", passwordResult.Errors.Select(e => e.Description));
            return AppResponse<UserProfileDto>.Error(errors);
        }

        try
        {
            await notificationService.CreateAndSendAsync(
                targetUserId: user.Id,
                type: NotificationType.Warning,
                title: "Đổi mật khẩu",
                message: "Mật khẩu của bạn đã được thay đổi thành công",
                relatedEntityType: "Account",
                categoryCode: "account",
                storeId: user.StoreId);
        }
        catch { }

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

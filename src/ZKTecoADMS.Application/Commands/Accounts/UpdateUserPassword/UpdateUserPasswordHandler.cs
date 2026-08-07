using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.DTOs.Users;
using ZKTecoADMS.Application.Helpers;
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
        if (string.IsNullOrWhiteSpace(request.CurrentPassword))
        {
            return AppResponse<UserProfileDto>.Error("Vui lòng nhập mật khẩu hiện tại");
        }

        if (string.IsNullOrWhiteSpace(request.NewPassword) || request.NewPassword.Length < 6)
        {
            return AppResponse<UserProfileDto>.Error("Mật khẩu mới phải có ít nhất 6 ký tự");
        }

        if (string.Equals(request.CurrentPassword, request.NewPassword, StringComparison.Ordinal))
        {
            return AppResponse<UserProfileDto>.Error("Mật khẩu mới phải khác mật khẩu hiện tại");
        }

        var user = await userManager.Users
            .Include(u => u.Manager)
            .FirstOrDefaultAsync(u => u.Id == request.UserId, cancellationToken);

        if (user == null)
        {
            return AppResponse<UserProfileDto>.Error("Không tìm thấy tài khoản");
        }

        var passwordResult = await userManager.ChangePasswordAsync(user, request.CurrentPassword, request.NewPassword);
        if (!passwordResult.Succeeded)
        {
            var errors = string.Join(", ", passwordResult.Errors.Select(MapPasswordError));
            return AppResponse<UserProfileDto>.Error(errors);
        }

        UserPasswordVisibility.ClearRememberedPassword(user);
        await userManager.UpdateAsync(user);

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

    private static string MapPasswordError(IdentityError e) => e.Code switch
    {
        "PasswordMismatch" => "Mật khẩu hiện tại không đúng",
        "PasswordTooShort" => "Mật khẩu mới quá ngắn (tối thiểu 6 ký tự)",
        "PasswordRequiresDigit" => "Mật khẩu cần có chữ số",
        "PasswordRequiresUpper" => "Mật khẩu cần có chữ hoa",
        "PasswordRequiresLower" => "Mật khẩu cần có chữ thường",
        "PasswordRequiresNonAlphanumeric" => "Mật khẩu cần có ký tự đặc biệt",
        _ => string.IsNullOrWhiteSpace(e.Description) ? "Không thể đổi mật khẩu" : e.Description
    };
}

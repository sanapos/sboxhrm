using Microsoft.AspNetCore.Identity;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Application.Commands.Accounts.UpdateEmployeeAccount;

public class UpdateEmployeeAccountHandler(
    UserManager<ApplicationUser> userManager,
    ISystemNotificationService notificationService
    ) : ICommandHandler<UpdateEmployeeAccountCommand, AppResponse<bool>>
{
    public async Task<AppResponse<bool>> Handle(UpdateEmployeeAccountCommand request, CancellationToken cancellationToken)
    {
        var user = await userManager.FindByIdAsync(request.UserId.ToString());
        if (user == null || user.StoreId != request.StoreId)
        {
            return AppResponse<bool>.Error("Không tìm thấy tài khoản.");
        }

        var previousEmail = user.Email;
        var previousRole = user.Role;
        var previousPhone = user.PhoneNumber;

        // Update user properties
        user.FirstName = request.FirstName;
        user.LastName = request.LastName;
        user.Email = request.Email;
        user.PhoneNumber = request.PhoneNumber;

        if (!string.IsNullOrWhiteSpace(request.UserName))
        {
            user.UserName = request.UserName;
            user.NormalizedUserName = request.UserName.ToUpperInvariant();
        }

        if (!string.IsNullOrWhiteSpace(request.Role))
        {
            if (!Enum.TryParse<Roles>(request.Role, ignoreCase: true, out _))
            {
                return AppResponse<bool>.Error($"Vai trò '{request.Role}' không hợp lệ.");
            }
            // Remove old roles and add new one
            var currentRoles = await userManager.GetRolesAsync(user);
            if (currentRoles.Any())
            {
                await userManager.RemoveFromRolesAsync(user, currentRoles);
            }
            await userManager.AddToRoleAsync(user, request.Role);
            user.Role = request.Role;
        }

        var result = await userManager.UpdateAsync(user);
        if (!result.Succeeded)
        {
            return AppResponse<bool>.Error(result.Errors.Select(e => e.Description).ToList());
        }

        // Notify the affected user about important account changes.
        try
        {
            var changes = new List<string>();
            if (!string.Equals(previousEmail, user.Email, StringComparison.OrdinalIgnoreCase))
                changes.Add($"email → {user.Email}");
            if (!string.Equals(previousRole, user.Role, StringComparison.OrdinalIgnoreCase))
                changes.Add($"vai trò → {user.Role}");
            if (!string.Equals(previousPhone, user.PhoneNumber, StringComparison.Ordinal))
                changes.Add("số điện thoại");

            if (changes.Count > 0)
            {
                var msg = "Tài khoản của bạn đã được cập nhật: " + string.Join(", ", changes);
                await notificationService.CreateAndSendAsync(
                    user.Id, NotificationType.Info,
                    "Thông tin tài khoản đã thay đổi", msg,
                    relatedEntityId: user.Id, relatedEntityType: "Account",
                    categoryCode: "account", storeId: request.StoreId);
            }
        }
        catch { /* best-effort */ }

        return AppResponse<bool>.Success(true);
    }
}

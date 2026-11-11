using Microsoft.AspNetCore.Identity;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Application.Commands.Accounts.UpdateEmployeeAccount;

public class UpdateEmployeeAccountHandler(
    UserManager<ApplicationUser> userManager,
    IRepository<Employee> employeeRepository,
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

        // Kiểm tra hồ sơ trước khi đổi gì: không gắn được thì giữ nguyên toàn bộ tài khoản.
        Employee? linkEmployee = null;
        if (request.EmployeeId is Guid employeeId && employeeId != Guid.Empty)
        {
            linkEmployee = await employeeRepository.GetByIdAsync(employeeId, cancellationToken: cancellationToken);
            var denyLink = EmployeeAccountLink.Deny(linkEmployee, request.StoreId, user.Id);
            if (denyLink != null)
            {
                return AppResponse<bool>.Error(denyLink);
            }
            var current = await employeeRepository.GetSingleAsync(
                e => e.ApplicationUserId == user.Id && e.Deleted == null && e.Id != employeeId,
                cancellationToken: cancellationToken);
            if (current != null)
            {
                return AppResponse<bool>.Error("Tài khoản này đã gắn với hồ sơ khác.");
            }
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

        if (linkEmployee != null && linkEmployee.ApplicationUserId != user.Id)
        {
            // Hồ sơ cũ đã xóa mềm vẫn giữ ApplicationUserId, mà cột này là unique — phải nhả ra trước khi gắn hồ sơ mới.
            var stale = await employeeRepository.GetSingleAsync(
                e => e.ApplicationUserId == user.Id && e.Deleted != null,
                cancellationToken: cancellationToken);
            if (stale != null)
            {
                stale.ApplicationUserId = null;
                await employeeRepository.UpdateAsync(stale, cancellationToken);
            }
            linkEmployee.ApplicationUserId = user.Id;
            await employeeRepository.UpdateAsync(linkEmployee, cancellationToken);
        }

        // Notify the affected user about important account changes.
        try
        {
            // «Tài khoản của bạn vừa thay đổi» / «Vai trò mới: Quản lý · Email: an@x.com · SĐT: 0901234567»
            var changes = new List<string>();
            if (!string.Equals(previousRole, user.Role, StringComparison.OrdinalIgnoreCase))
                changes.Add($"Vai trò mới: {RoleLabel(user.Role)}");
            if (!string.Equals(previousEmail, user.Email, StringComparison.OrdinalIgnoreCase))
                changes.Add(string.IsNullOrWhiteSpace(user.Email) ? "Đã bỏ email" : $"Email: {user.Email}");
            if (!string.Equals(previousPhone, user.PhoneNumber, StringComparison.Ordinal))
                changes.Add(string.IsNullOrWhiteSpace(user.PhoneNumber) ? "Đã bỏ SĐT" : $"SĐT: {user.PhoneNumber}");

            if (changes.Count > 0)
            {
                var msg = string.Join(" · ", changes);
                await notificationService.CreateAndSendAsync(
                    user.Id, NotificationType.Info,
                    "Tài khoản của bạn vừa thay đổi", msg,
                    relatedEntityId: user.Id, relatedEntityType: "Account",
                    categoryCode: "account", storeId: request.StoreId);
            }
        }
        catch { /* best-effort */ }

        return AppResponse<bool>.Success(true);
    }

    /// <summary>Mã vai trò (Manager, Employee…) → nhãn tiếng Việt cho thông báo.</summary>
    private static string RoleLabel(string? role) => role?.Trim().ToLowerInvariant() switch
    {
        "superadmin" => "Quản trị hệ thống",
        "admin" => "Chủ cửa hàng / Quản trị",
        "director" => "Giám đốc",
        "manager" => "Quản lý",
        "departmenthead" => "Trưởng phòng",
        "accountant" => "Kế toán",
        "cashier" => "Thu ngân",
        "waiter" => "Phục vụ",
        "employee" => "Nhân viên",
        "agent" => "Đại lý",
        "user" => "Người dùng",
        null or "" => "Chưa có",
        _ => role!,
    };
}

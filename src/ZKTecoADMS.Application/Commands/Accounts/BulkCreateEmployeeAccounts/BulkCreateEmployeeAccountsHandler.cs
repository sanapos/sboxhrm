using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.DTOs.Accounts;
using ZKTecoADMS.Application.DTOs.Commons;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.Accounts.BulkCreateEmployeeAccounts;

public class BulkCreateEmployeeAccountsHandler(
    UserManager<ApplicationUser> userManager,
    IRepository<Employee> employeeRepository,
    ISystemNotificationService notificationService
) : ICommandHandler<BulkCreateEmployeeAccountsCommand, AppResponse<BulkCreateEmployeeAccountsResult>>
{
    public async Task<AppResponse<BulkCreateEmployeeAccountsResult>> Handle(
        BulkCreateEmployeeAccountsCommand request,
        CancellationToken cancellationToken)
    {
        if (request.EmployeeIds.Count == 0)
        {
            return AppResponse<BulkCreateEmployeeAccountsResult>.Error(
                "Vui lòng chọn ít nhất một nhân viên.");
        }

        if (string.IsNullOrWhiteSpace(request.Password) || request.Password.Length < 6)
        {
            return AppResponse<BulkCreateEmployeeAccountsResult>.Error(
                "Mật khẩu tối thiểu 6 ký tự.");
        }

        var roleName = string.IsNullOrWhiteSpace(request.Role)
            ? nameof(Roles.Employee)
            : request.Role.Trim();
        if (!Enum.TryParse<Roles>(roleName, ignoreCase: true, out _))
        {
            return AppResponse<BulkCreateEmployeeAccountsResult>.Error(
                $"Vai trò '{roleName}' không hợp lệ.");
        }

        var manager = await userManager.FindByIdAsync(request.ManagerId.ToString());
        if (manager == null)
        {
            return AppResponse<BulkCreateEmployeeAccountsResult>.Error("Không tìm thấy quản lý.");
        }

        var isManager = await userManager.IsInRoleAsync(manager, nameof(Roles.Manager));
        var isAdmin = await userManager.IsInRoleAsync(manager, nameof(Roles.Admin));
        if (!isManager && !isAdmin)
        {
            return AppResponse<BulkCreateEmployeeAccountsResult>.Error(
                "Bạn không có quyền tạo tài khoản.");
        }

        var employees = await employeeRepository.GetAllAsync(
            e => request.EmployeeIds.Contains(e.Id),
            cancellationToken: cancellationToken);
        var employeeMap = employees.ToDictionary(e => e.Id);

        var result = new BulkCreateEmployeeAccountsResult();

        foreach (var employeeId in request.EmployeeIds.Distinct())
        {
            if (!employeeMap.TryGetValue(employeeId, out var employee))
            {
                result.Items.Add(new BulkCreateEmployeeAccountItemResult
                {
                    EmployeeId = employeeId,
                    Success = false,
                    Message = "Không tìm thấy nhân viên"
                });
                result.Failed++;
                continue;
            }

            var displayName = $"{employee.LastName} {employee.FirstName}".Trim();
            var item = new BulkCreateEmployeeAccountItemResult
            {
                EmployeeId = employee.Id,
                EmployeeCode = employee.EmployeeCode,
                EmployeeName = displayName
            };

            if (employee.ApplicationUserId.HasValue)
            {
                item.Skipped = true;
                item.Success = false;
                item.Message = "Đã có tài khoản";
                result.Skipped++;
                result.Items.Add(item);
                continue;
            }

            if (employee.StoreId.HasValue && manager.StoreId.HasValue &&
                employee.StoreId != manager.StoreId)
            {
                item.Success = false;
                item.Message = "Nhân viên thuộc cửa hàng khác";
                result.Failed++;
                result.Items.Add(item);
                continue;
            }

            var contacts = await ResolveLoginContactsAsync(employee, manager.StoreId);
            if (contacts.Error != null)
            {
                item.Success = false;
                item.Message = contacts.Error;
                result.Failed++;
                result.Items.Add(item);
                continue;
            }

            var userName = await ResolveUniqueUserNameAsync(employee);
            var email = contacts.Email;
            var phone = contacts.Phone;

            var newUser = new ApplicationUser
            {
                UserName = userName,
                Email = email,
                FirstName = employee.FirstName,
                LastName = employee.LastName,
                PhoneNumber = phone,
                CreatedAt = DateTime.Now,
                EmailConfirmed = true,
                PhoneNumberConfirmed = true,
                ManagerId = request.ManagerId,
                StoreId = manager.StoreId,
                Role = roleName
            };
            UserPasswordVisibility.RememberPassword(newUser, request.Password);

            var createResult = await userManager.CreateAsync(newUser, request.Password);
            if (!createResult.Succeeded)
            {
                item.Success = false;
                item.Message = string.Join("; ", createResult.Errors.Select(e => e.Description));
                result.Failed++;
                result.Items.Add(item);
                continue;
            }

            var roleResult = await userManager.AddToRoleAsync(newUser, roleName);
            if (!roleResult.Succeeded)
            {
                await userManager.DeleteAsync(newUser);
                item.Success = false;
                item.Message = string.Join("; ", roleResult.Errors.Select(e => e.Description));
                result.Failed++;
                result.Items.Add(item);
                continue;
            }

            employee.ApplicationUserId = newUser.Id;
            await employeeRepository.UpdateAsync(employee);

            item.Success = true;
            item.UserName = userName;
            item.Email = email;
            item.PhoneNumber = phone;
            item.Message = "Đã tạo tài khoản";
            result.Created++;
            result.Items.Add(item);

            try
            {
                var loginHint = !string.IsNullOrEmpty(email) && !string.IsNullOrEmpty(phone)
                    ? $"Đăng nhập bằng email {email} hoặc SĐT {phone}. Có thể đổi mật khẩu sau khi đăng nhập."
                    : !string.IsNullOrEmpty(email)
                        ? $"Đăng nhập bằng email {email}. Có thể đổi mật khẩu sau khi đăng nhập."
                        : $"Đăng nhập bằng SĐT {phone}. Có thể đổi mật khẩu sau khi đăng nhập.";
                await notificationService.CreateAndSendAsync(
                    targetUserId: newUser.Id,
                    type: NotificationType.Success,
                    title: "Tài khoản đã tạo",
                    message: loginHint,
                    relatedEntityId: newUser.Id,
                    relatedEntityType: "Account",
                    categoryCode: "account",
                    storeId: manager.StoreId);
            }
            catch { }
        }

        return AppResponse<BulkCreateEmployeeAccountsResult>.Success(result);
    }

    private static string SanitizeUserName(string code)
    {
        if (string.IsNullOrWhiteSpace(code)) return string.Empty;
        return new string(code.Trim()
            .Where(c => char.IsLetterOrDigit(c) || c == '.' || c == '_' || c == '-')
            .ToArray());
    }

    private async Task<string> ResolveUniqueUserNameAsync(Employee employee)
    {
        var baseName = SanitizeUserName(employee.EmployeeCode);
        if (string.IsNullOrEmpty(baseName))
        {
            baseName = $"nv{employee.Id.ToString("N")[..8]}";
        }

        var candidate = baseName;
        var suffix = 1;
        while (await userManager.FindByNameAsync(candidate) != null)
        {
            suffix++;
            candidate = $"{baseName}{suffix}";
        }

        return candidate;
    }

    private sealed record LoginContacts(string? Email, string? Phone, string? Error);

    /// <summary>Cần ít nhất email hoặc SĐT từ hồ sơ HR để đăng nhập.</summary>
    private async Task<LoginContacts> ResolveLoginContactsAsync(Employee employee, Guid? storeId)
    {
        var profileEmail = !string.IsNullOrWhiteSpace(employee.CompanyEmail)
            ? employee.CompanyEmail.Trim()
            : !string.IsNullOrWhiteSpace(employee.PersonalEmail)
                ? employee.PersonalEmail.Trim()
                : null;
        var profilePhone = NormalizePhone(employee.PhoneNumber);

        if (string.IsNullOrEmpty(profileEmail) && string.IsNullOrEmpty(profilePhone))
        {
            return new LoginContacts(null, null, "Nhân viên chưa có email và SĐT trong hồ sơ");
        }

        string? email = null;
        string? phone = null;

        if (!string.IsNullOrEmpty(profileEmail))
        {
            if (await userManager.FindByEmailAsync(profileEmail) == null)
            {
                email = profileEmail;
            }
        }

        if (!string.IsNullOrEmpty(profilePhone))
        {
            var phoneTaken = await userManager.Users.AnyAsync(u =>
                u.PhoneNumber == profilePhone &&
                (!storeId.HasValue || u.StoreId == storeId));
            if (!phoneTaken)
            {
                phone = profilePhone;
            }
        }

        if (string.IsNullOrEmpty(email) && string.IsNullOrEmpty(phone))
        {
            if (!string.IsNullOrEmpty(profileEmail) && !string.IsNullOrEmpty(profilePhone))
            {
                return new LoginContacts(null, null,
                    "Email và SĐT đều đã được dùng cho tài khoản khác");
            }

            if (!string.IsNullOrEmpty(profileEmail))
            {
                return new LoginContacts(null, null, "Email đã được dùng cho tài khoản khác");
            }

            return new LoginContacts(null, null, "SĐT đã được dùng cho tài khoản khác");
        }

        return new LoginContacts(email, phone, null);
    }

    private static string? NormalizePhone(string? phone)
    {
        if (string.IsNullOrWhiteSpace(phone)) return null;
        var digits = new string(phone.Where(char.IsDigit).ToArray());
        return digits.Length >= 9 ? digits : phone.Trim();
    }
}

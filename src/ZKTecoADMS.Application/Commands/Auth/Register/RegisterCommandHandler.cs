using System.Text.RegularExpressions;
using ZKTecoADMS.Application.CQRS;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Application.Interfaces;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using ZKTecoADMS.Application.Settings;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Application.Services;
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Application.Commands.Auth.Register;

public class RegisterCommandHandler(
    UserManager<ApplicationUser> userManager,
    IRepository<Store> storeRepository,
    IRepository<Department> departmentRepository,
    IRepository<ShiftTemplate> shiftTemplateRepository,
    IRepository<Holiday> holidayRepository,
    IRepository<PenaltySetting> penaltySettingRepository,
    IRepository<Allowance> allowanceRepository,
    IRepository<Permission> permissionRepository,
    IRepository<RolePermission> rolePermissionRepository,
    IRepository<Agent> agentRepository,
    IRepository<ServicePackage> servicePackageRepository,
    IEmailService emailService,
    IOptions<EmailSettings> emailSettings,
    ISystemNotificationService notificationService,
    IStoreAgentLinkService storeAgentLinkService,
    ILogger<RegisterCommandHandler> logger) : ICommandHandler<RegisterCommand, AppResponse<string>>
{
    public async Task<AppResponse<string>> Handle(RegisterCommand command, CancellationToken cancellationToken)
    {
        var request = command.RegisterRequest;
        var normalizedPhone = NormalizePhone(request.PhoneNumber);
        if (normalizedPhone.Length < 9)
        {
            return AppResponse<string>.Error("Số điện thoại không hợp lệ.");
        }

        var existingUser = await userManager.FindByEmailAsync(request.Email.Trim());
        if (existingUser != null)
        {
            return AppResponse<string>.Error("Email này đã được sử dụng.");
        }

        var storeCode = !string.IsNullOrWhiteSpace(request.StoreCode)
            ? SanitizeStoreCode(request.StoreCode)
            : GenerateStoreCode(request.StoreName);

        if (string.IsNullOrWhiteSpace(storeCode))
        {
            return AppResponse<string>.Error("Mã doanh nghiệp không hợp lệ. Vui lòng nhập lại.");
        }

        var existingStore = await storeRepository.GetSingleAsync(
            s => s.Code.ToLower() == storeCode.ToLower(),
            cancellationToken: cancellationToken);
        if (existingStore != null)
        {
            return AppResponse<string>.Error(
                $"Mã cửa hàng '{storeCode}' đã tồn tại. Vui lòng chọn mã khác.");
        }

        var phoneConflict = await FindPhoneConflictMessageAsync(normalizedPhone, cancellationToken);
        if (phoneConflict != null)
        {
            return AppResponse<string>.Error(phoneConflict);
        }

        Guid? agentId = null;
        var rawAgentCode = FirstNonEmpty(
            request.AgentCode,
            request.Agent,
            request.Ref);
        if (!string.IsNullOrWhiteSpace(rawAgentCode))
        {
            var code = rawAgentCode.Trim().ToUpper();
            var agent = await agentRepository.GetSingleAsync(
                a => a.Code.ToUpper() == code && a.IsActive,
                cancellationToken: cancellationToken);
            if (agent == null)
            {
                return AppResponse<string>.Error(
                    $"Mã đại lý '{rawAgentCode}' không tồn tại hoặc đã ngừng hoạt động.");
            }

            agentId = agent.Id;
            var linkedStores = await storeRepository.CountAsync(
                s => s.AgentId == agent.Id,
                cancellationToken: cancellationToken);
            if (agent.MaxStores > 0 && linkedStores >= agent.MaxStores)
            {
                return AppResponse<string>.Error(
                    $"Đại lý '{agent.Code}' đã đạt giới hạn {agent.MaxStores} cửa hàng. Vui lòng liên hệ đại lý hoặc quản trị.");
            }
        }

        ServicePackage? selectedPackage = null;
        if (request.ServicePackageId.HasValue)
        {
            selectedPackage = await servicePackageRepository.GetSingleAsync(
                p => p.Id == request.ServicePackageId.Value && p.IsActive,
                cancellationToken: cancellationToken);
            if (selectedPackage == null)
            {
                return AppResponse<string>.Error(
                    "Gói dịch vụ được chọn không tồn tại hoặc đã ngừng hoạt động.");
            }
        }

        var userId = Guid.NewGuid();
        var storeId = Guid.NewGuid();
        var storeCreated = false;

        try
        {
            var store = new Store
            {
                Id = storeId,
                Name = request.StoreName.Trim(),
                Code = storeCode,
                Province = request.Province.Trim(),
                Phone = request.PhoneNumber.Trim(),
                IsActive = true,
                CreatedAt = DateTime.UtcNow,
                OwnerId = null,
                AgentId = agentId,
                ServicePackageId = selectedPackage?.Id,
                TrialDays = selectedPackage?.DefaultDurationDays ?? 14,
                MaxUsers = selectedPackage?.MaxUsers ?? 10,
                MaxDevices = selectedPackage?.MaxDevices ?? 2,
                TrialStartDate = DateTime.UtcNow
            };
            await storeRepository.AddAsync(store, cancellationToken);
            storeCreated = true;

            if (agentId.HasValue)
            {
                var (linked, linkError) = await storeAgentLinkService.LinkStoreToAgentAsync(
                    storeId,
                    agentId.Value,
                    "register",
                    cancellationToken);
                if (!linked)
                {
                    await RollbackFailedRegistrationAsync(storeId, cancellationToken);
                    return AppResponse<string>.Error(
                        linkError ?? "Không thể gán cửa hàng cho đại lý. Vui lòng thử lại.");
                }
            }

            try
            {
                await StoreDefaultSetupSeeder.SeedDepartmentsIfEmptyAsync(
                    departmentRepository, storeId, "Register", cancellationToken);
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex, "Could not seed default departments for store {StoreId}", storeId);
            }

            var user = new ApplicationUser
            {
                Id = userId,
                UserName = request.Email.Trim(),
                Email = request.Email.Trim(),
                PhoneNumber = request.PhoneNumber.Trim(),
                FirstName = request.StoreName.Trim(),
                LastName = "Owner",
                EmailConfirmed = true,
                PhoneNumberConfirmed = true,
                CreatedAt = DateTime.UtcNow,
                StoreId = storeId,
                Role = nameof(Roles.Admin)
            };
            UserPasswordVisibility.RememberPassword(user, request.Password);

            var result = await userManager.CreateAsync(user, request.Password);
            if (!result.Succeeded)
            {
                await RollbackFailedRegistrationAsync(storeId, cancellationToken);
                return AppResponse<string>.Error(
                    result.Errors.Select(TranslateIdentityError));
            }

            var roleResult = await userManager.AddToRoleAsync(user, nameof(Roles.Admin));
            if (!roleResult.Succeeded)
            {
                await userManager.DeleteAsync(user);
                await RollbackFailedRegistrationAsync(storeId, cancellationToken);
                return AppResponse<string>.Error(
                    roleResult.Errors.Select(TranslateIdentityError));
            }

            store.OwnerId = userId;
            await storeRepository.UpdateAsync(store, cancellationToken);

            try
            {
                await StoreDefaultSetupSeeder.SeedSettingsIfEmptyAsync(
                    storeId,
                    userId,
                    shiftTemplateRepository,
                    holidayRepository,
                    penaltySettingRepository,
                    allowanceRepository,
                    "Register",
                    cancellationToken);
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex, "Could not seed default settings for store {StoreId}", storeId);
            }

            try
            {
                await StoreDefaultSetupSeeder.SeedRolePermissionsIfEmptyAsync(
                    permissionRepository,
                    rolePermissionRepository,
                    storeId,
                    cancellationToken);
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex, "Could not seed default role permissions for store {StoreId}", storeId);
            }

            try
            {
                var loginUrl = emailSettings.Value.ResetPasswordBaseUrl ?? "http://localhost:8080";
                await emailService.SendWelcomeEmailAsync(
                    request.Email.Trim(),
                    request.StoreName.Trim(),
                    storeCode,
                    loginUrl);
                logger.LogInformation(
                    "Welcome email sent to {Email} for store {StoreCode}",
                    request.Email,
                    storeCode);
            }
            catch (Exception ex)
            {
                logger.LogWarning(
                    ex,
                    "Failed to send welcome email to {Email}, but registration succeeded",
                    request.Email);
            }

            try
            {
                var superAdmins = await userManager.GetUsersInRoleAsync(nameof(Roles.SuperAdmin));
                var superAdminIds = superAdmins.Select(u => u.Id).ToList();
                if (superAdminIds.Count > 0)
                {
                    await notificationService.CreateAndSendToUsersAsync(
                        targetUserIds: superAdminIds,
                        type: NotificationType.Info,
                        title: "Cửa hàng mới đăng ký",
                        message:
                            $"Cửa hàng '{request.StoreName}' (Mã: {storeCode}) vừa đăng ký. Email: {request.Email}",
                        relatedUrl: "/admin/stores",
                        relatedEntityId: storeId,
                        relatedEntityType: "Store",
                        categoryCode: "store");
                }
            }
            catch (Exception ex)
            {
                logger.LogWarning(
                    ex,
                    "Failed to notify SuperAdmins about new store registration {StoreCode}",
                    storeCode);
            }

            return AppResponse<string>.Success(
                $"Đăng ký cửa hàng thành công! Mã cửa hàng của bạn là: {storeCode}. Hãy ghi nhớ mã này để đăng nhập.");
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Registration failed for store code {StoreCode}", storeCode);
            if (storeCreated)
            {
                await RollbackFailedRegistrationAsync(storeId, cancellationToken);
            }

            return AppResponse<string>.Error(
                "Không thể hoàn tất đăng ký. Vui lòng thử lại sau hoặc liên hệ hỗ trợ.");
        }
    }

    private async Task<string?> FindPhoneConflictMessageAsync(
        string normalizedPhone,
        CancellationToken cancellationToken)
    {
        var userPhones = await userManager.Users
            .Where(u => u.PhoneNumber != null && u.PhoneNumber != "")
            .Select(u => u.PhoneNumber!)
            .ToListAsync(cancellationToken);
        if (userPhones.Any(p => NormalizePhone(p) == normalizedPhone))
        {
            return "Số điện thoại này đã được sử dụng.";
        }

        var storePhones = await storeRepository.GetAllAsync(
            s => s.Phone != null && s.Phone != "",
            cancellationToken: cancellationToken);
        if (storePhones.Any(s => NormalizePhone(s.Phone!) == normalizedPhone))
        {
            return "Số điện thoại này đã được sử dụng cho cửa hàng khác.";
        }

        return null;
    }

    private async Task RollbackFailedRegistrationAsync(Guid storeId, CancellationToken cancellationToken)
    {
        try
        {
            await departmentRepository.DeleteAsync(
                d => d.StoreId == storeId,
                cancellationToken);
            await storeRepository.DeleteByIdAsync(storeId, cancellationToken);
            logger.LogWarning("Rolled back incomplete registration for store {StoreId}", storeId);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Failed to rollback registration artifacts for store {StoreId}", storeId);
        }
    }

    private static string? FirstNonEmpty(params string?[] values)
    {
        foreach (var value in values)
        {
            if (!string.IsNullOrWhiteSpace(value))
            {
                return value.Trim();
            }
        }

        return null;
    }

    private static string NormalizePhone(string? phone)
    {
        if (string.IsNullOrWhiteSpace(phone)) return string.Empty;
        var digits = Regex.Replace(phone.Trim(), @"[^\d]", "");
        if (digits.StartsWith("84") && digits.Length >= 11)
        {
            digits = "0" + digits[2..];
        }

        return digits;
    }

    private static string TranslateIdentityError(IdentityError error)
    {
        return error.Code switch
        {
            "DuplicateUserName" or "DuplicateEmail" => "Email này đã được sử dụng.",
            "DuplicatePhoneNumber" => "Số điện thoại này đã được sử dụng.",
            "PasswordTooShort" => "Mật khẩu phải có ít nhất 6 ký tự.",
            "PasswordRequiresNonAlphanumeric" => "Mật khẩu cần có ký tự đặc biệt.",
            "PasswordRequiresDigit" => "Mật khẩu cần có ít nhất một chữ số.",
            "PasswordRequiresUpper" => "Mật khẩu cần có chữ hoa.",
            "PasswordRequiresLower" => "Mật khẩu cần có chữ thường.",
            _ => string.IsNullOrWhiteSpace(error.Description)
                ? "Không thể tạo tài khoản."
                : error.Description
        };
    }

    private static string GenerateStoreCode(string storeName) => SanitizeStoreCode(storeName);

    private static string SanitizeStoreCode(string input)
    {
        var code = input.ToLowerInvariant();
        code = RemoveVietnameseAccents(code);
        code = Regex.Replace(code, @"[^a-z0-9]", "");
        if (code.Length > 20) code = code[..20];
        return code;
    }

    private static string RemoveVietnameseAccents(string text)
    {
        string[] vietnameseChars =
        [
            "aàảãáạăằẳẵắặâầẩẫấậ",
            "dđ",
            "eèẻẽéẹêềểễếệ",
            "iìỉĩíị",
            "oòỏõóọôồổỗốộơờởỡớợ",
            "uùủũúụưừửữứự",
            "yỳỷỹýỵ"
        ];

        foreach (var chars in vietnameseChars)
        {
            for (var i = 1; i < chars.Length; i++)
            {
                text = text.Replace(chars[i], chars[0]);
            }
        }

        return text;
    }
}

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
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Application.Commands.Auth.Register;

public class RegisterCommandHandler(
    UserManager<ApplicationUser> userManager,
    IRepository<Store> storeRepository,
    IEmailService emailService,
    IOptions<EmailSettings> emailSettings,
    ISystemNotificationService notificationService,
    ILogger<RegisterCommandHandler> logger) : ICommandHandler<RegisterCommand, AppResponse<string>>
{
    public async Task<AppResponse<string>> Handle(RegisterCommand command, CancellationToken cancellationToken)
    {
        var request = command.RegisterRequest;
        
        // Kiểm tra email đã tồn tại chưa
        var existingUser = await userManager.FindByEmailAsync(request.Email);
        if (existingUser != null)
        {
            return AppResponse<string>.Error("Email này đã được sử dụng.");
        }
        
        // Tạo mã cửa hàng: dùng mã tùy chỉnh nếu có, nếu không thì tự động tạo từ tên
        var storeCode = !string.IsNullOrWhiteSpace(request.StoreCode) 
            ? SanitizeStoreCode(request.StoreCode) 
            : GenerateStoreCode(request.StoreName);
        
        // Kiểm tra mã cửa hàng đã tồn tại chưa
        var existingStore = await storeRepository.GetSingleAsync(
            s => s.Code.ToLower() == storeCode.ToLower(), 
            cancellationToken: cancellationToken);
        if (existingStore != null)
        {
            return AppResponse<string>.Error($"Mã cửa hàng '{storeCode}' đã tồn tại. Vui lòng đổi tên cửa hàng khác.");
        }
        
        var userId = Guid.NewGuid();
        var storeId = Guid.NewGuid();
        
        // 1. Tạo Store trước (chưa có OwnerId)
        var store = new Store
        {
            Id = storeId,
            Name = request.StoreName,
            Code = storeCode,
            IsActive = true,
            CreatedAt = DateTime.UtcNow,
            OwnerId = null // Chưa có owner, sẽ cập nhật sau
        };
        await storeRepository.AddAsync(store, cancellationToken);
        
        // Kiểm tra số điện thoại đã tồn tại chưa
        if (!string.IsNullOrEmpty(request.PhoneNumber))
        {
            var existingPhone = await userManager.Users
                .AnyAsync(u => u.PhoneNumber == request.PhoneNumber, cancellationToken);
            if (existingPhone)
            {
                return AppResponse<string>.Error("Số điện thoại này đã được sử dụng.");
            }
        }

        // 2. Tạo User với StoreId đã tồn tại
        var user = new ApplicationUser
        {
            Id = userId,
            UserName = request.Email,
            Email = request.Email,
            PhoneNumber = request.PhoneNumber,
            FirstName = request.StoreName, // Dùng tên cửa hàng làm FirstName
            LastName = "Owner",
            EmailConfirmed = true,
            PhoneNumberConfirmed = true,
            CreatedAt = DateTime.UtcNow,
            StoreId = storeId,
            Role = nameof(Roles.Admin)
        };
        
        var result = await userManager.CreateAsync(user, request.Password);
        if (!result.Succeeded)
        {
            return AppResponse<string>.Error(result.Errors.Select(e => e.Description));
        }

        // 3. Gán role Admin cho owner
        await userManager.AddToRoleAsync(user, nameof(Roles.Admin));
        
        // 4. Cập nhật OwnerId cho Store
        store.OwnerId = userId;
        await storeRepository.UpdateAsync(store, cancellationToken);

        // 5. Gửi email chào mừng với thông tin tài khoản
        try
        {
            var loginUrl = emailSettings.Value.ResetPasswordBaseUrl ?? "http://localhost:8080";
            await emailService.SendWelcomeEmailAsync(
                request.Email,
                request.StoreName,
                storeCode,
                loginUrl
            );
            logger.LogInformation("Welcome email sent to {Email} for store {StoreCode}", request.Email, storeCode);
        }
        catch (Exception ex)
        {
            // Không fail đăng ký chỉ vì gửi email thất bại
            logger.LogWarning(ex, "Failed to send welcome email to {Email}, but registration succeeded", request.Email);
        }

        // 6. Thông báo cho SuperAdmin có cửa hàng mới đăng ký
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
                    message: $"Cửa hàng '{request.StoreName}' (Mã: {storeCode}) vừa đăng ký. Email: {request.Email}",
                    relatedEntityId: storeId,
                    relatedEntityType: "Store",
                    categoryCode: "store");
            }
        }
        catch { }

        return AppResponse<string>.Success($"Đăng ký cửa hàng thành công! Mã cửa hàng của bạn là: {storeCode}. Hãy ghi nhớ mã này để đăng nhập.");
    }
    
    // Tạo mã cửa hàng từ tên (VD: "SANA POS Shop" -> "sanaposshop")
    private static string GenerateStoreCode(string storeName)
    {
        return SanitizeStoreCode(storeName);
    }
    
    // Chuẩn hóa mã cửa hàng: chữ thường, bỏ dấu, chỉ giữ a-z0-9
    private static string SanitizeStoreCode(string input)
    {
        // Chuyển thành chữ thường, loại bỏ dấu và ký tự đặc biệt
        var code = input.ToLowerInvariant();
        
        // Loại bỏ dấu tiếng Việt
        code = RemoveVietnameseAccents(code);
        
        // Chỉ giữ lại chữ cái và số
        code = Regex.Replace(code, @"[^a-z0-9]", "");
        
        // Giới hạn độ dài
        if (code.Length > 20) code = code[..20];
        
        return code;
    }
    
    private static string RemoveVietnameseAccents(string text)
    {
        string[] vietnameseChars = new string[]
        {
            "aàảãáạăằẳẵắặâầẩẫấậ",
            "dđ",
            "eèẻẽéẹêềểễếệ",
            "iìỉĩíị",
            "oòỏõóọôồổỗốộơờởỡớợ",
            "uùủũúụưừửữứự",
            "yỳỷỹýỵ"
        };
        
        foreach (var chars in vietnameseChars)
        {
            for (int i = 1; i < chars.Length; i++)
            {
                text = text.Replace(chars[i], chars[0]);
            }
        }
        
        return text;
    }
}

using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Application.Helpers;

/// <summary>
/// Lưu mật khẩu dạng plain text để Super Admin tra cứu (chỉ khi admin tạo/đặt lại).
/// </summary>
public static class UserPasswordVisibility
{
    public static void RememberPassword(ApplicationUser user, string? password)
    {
        if (!string.IsNullOrWhiteSpace(password))
        {
            user.PlainTextPassword = password;
        }
    }

    public static void ClearRememberedPassword(ApplicationUser user)
    {
        user.PlainTextPassword = null;
    }
}

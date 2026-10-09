using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Application.Helpers;

/// <summary>
/// Trước đây lưu mật khẩu plain text để Super Admin tra cứu — đã bỏ (lộ DB / backup / token admin
/// là lộ mật khẩu người dùng). Giữ API để không đổi nơi gọi; mọi lời gọi chỉ xoá giá trị cũ.
/// Super Admin xem mật khẩu vừa đặt ngay trên màn hình lúc đặt lại, không lưu server.
/// </summary>
public static class UserPasswordVisibility
{
    public static void RememberPassword(ApplicationUser user, string? password)
    {
        user.PlainTextPassword = null;
    }

    public static void ClearRememberedPassword(ApplicationUser user)
    {
        user.PlainTextPassword = null;
    }
}

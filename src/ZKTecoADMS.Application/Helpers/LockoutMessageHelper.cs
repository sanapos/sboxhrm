using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Application.Helpers;

public static class LockoutMessageHelper
{
    /// <summary>
    /// Số phút còn lại trước khi có thể đăng nhập lại (làm tròn lên, tối thiểu 1).
    /// </summary>
    public static int? GetRemainingMinutes(ApplicationUser user)
    {
        if (user.LockoutEnd == null) return null;
        var remaining = user.LockoutEnd.Value - DateTimeOffset.UtcNow;
        if (remaining <= TimeSpan.Zero) return null;
        var mins = (int)Math.Ceiling(remaining.TotalMinutes);
        return mins < 1 ? 1 : mins;
    }

    public static string GetLockedMessage(ApplicationUser user, bool adminPortal = false)
    {
        var minutes = GetRemainingMinutes(user);
        if (minutes == null)
        {
            return adminPortal
                ? "Tài khoản đã bị khóa. Vui lòng thử lại sau hoặc liên hệ quản trị hệ thống."
                : "Tài khoản đã bị khóa. Vui lòng thử lại sau hoặc dùng Quên mật khẩu.";
        }

        return adminPortal
            ? $"Tài khoản đã bị khóa. Bạn có thể đăng nhập lại sau {minutes} phút."
            : $"Tài khoản đã bị khóa. Bạn có thể đăng nhập lại sau {minutes} phút hoặc dùng Quên mật khẩu.";
    }
}

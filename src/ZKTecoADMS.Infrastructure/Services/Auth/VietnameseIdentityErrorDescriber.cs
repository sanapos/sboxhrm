using Microsoft.AspNetCore.Identity;

namespace ZKTecoADMS.Infrastructure.Services.Auth;

/// <summary>
/// Lỗi ASP.NET Identity bằng tiếng Việt — mặc định trả tiếng Anh («Username '…' is already taken.»)
/// thẳng ra app khi tạo tài khoản nhân viên, đổi mật khẩu… Mã lỗi (Code) giữ nguyên.
/// </summary>
public class VietnameseIdentityErrorDescriber : IdentityErrorDescriber
{
    public override IdentityError DuplicateUserName(string userName) =>
        new() { Code = nameof(DuplicateUserName), Description = $"Tên đăng nhập '{userName}' đã được sử dụng." };

    public override IdentityError DuplicateEmail(string email) =>
        new() { Code = nameof(DuplicateEmail), Description = $"Email '{email}' đã được sử dụng." };

    public override IdentityError InvalidUserName(string? userName) =>
        new() { Code = nameof(InvalidUserName), Description = $"Tên đăng nhập '{userName}' không hợp lệ (chỉ dùng chữ không dấu, số và - . _ @ +)." };

    public override IdentityError InvalidEmail(string? email) =>
        new() { Code = nameof(InvalidEmail), Description = $"Email '{email}' không hợp lệ." };

    public override IdentityError PasswordMismatch() =>
        new() { Code = nameof(PasswordMismatch), Description = "Mật khẩu không đúng." };

    public override IdentityError InvalidToken() =>
        new() { Code = nameof(InvalidToken), Description = "Mã xác thực không hợp lệ hoặc đã hết hạn." };

    public override IdentityError PasswordTooShort(int length) =>
        new() { Code = nameof(PasswordTooShort), Description = $"Mật khẩu phải có ít nhất {length} ký tự." };

    public override IdentityError PasswordRequiresUniqueChars(int uniqueChars) =>
        new() { Code = nameof(PasswordRequiresUniqueChars), Description = $"Mật khẩu cần ít nhất {uniqueChars} ký tự khác nhau." };

    public override IdentityError PasswordRequiresNonAlphanumeric() =>
        new() { Code = nameof(PasswordRequiresNonAlphanumeric), Description = "Mật khẩu cần có ký tự đặc biệt." };

    public override IdentityError PasswordRequiresDigit() =>
        new() { Code = nameof(PasswordRequiresDigit), Description = "Mật khẩu cần có ít nhất một chữ số." };

    public override IdentityError PasswordRequiresLower() =>
        new() { Code = nameof(PasswordRequiresLower), Description = "Mật khẩu cần có chữ thường." };

    public override IdentityError PasswordRequiresUpper() =>
        new() { Code = nameof(PasswordRequiresUpper), Description = "Mật khẩu cần có chữ hoa." };

    public override IdentityError UserAlreadyHasPassword() =>
        new() { Code = nameof(UserAlreadyHasPassword), Description = "Tài khoản đã có mật khẩu." };

    public override IdentityError UserLockoutNotEnabled() =>
        new() { Code = nameof(UserLockoutNotEnabled), Description = "Tài khoản không bật khóa đăng nhập." };

    public override IdentityError UserAlreadyInRole(string role) =>
        new() { Code = nameof(UserAlreadyInRole), Description = $"Tài khoản đã có vai trò '{role}'." };

    public override IdentityError UserNotInRole(string role) =>
        new() { Code = nameof(UserNotInRole), Description = $"Tài khoản không có vai trò '{role}'." };

    public override IdentityError DuplicateRoleName(string role) =>
        new() { Code = nameof(DuplicateRoleName), Description = $"Vai trò '{role}' đã tồn tại." };

    public override IdentityError InvalidRoleName(string? role) =>
        new() { Code = nameof(InvalidRoleName), Description = $"Tên vai trò '{role}' không hợp lệ." };

    public override IdentityError ConcurrencyFailure() =>
        new() { Code = nameof(ConcurrencyFailure), Description = "Dữ liệu đã bị người khác sửa, vui lòng tải lại và thử lại." };

    public override IdentityError DefaultError() =>
        new() { Code = nameof(DefaultError), Description = "Có lỗi xảy ra, vui lòng thử lại." };

    public override IdentityError LoginAlreadyAssociated() =>
        new() { Code = nameof(LoginAlreadyAssociated), Description = "Tài khoản đăng nhập ngoài này đã được liên kết." };

    public override IdentityError RecoveryCodeRedemptionFailed() =>
        new() { Code = nameof(RecoveryCodeRedemptionFailed), Description = "Mã khôi phục không đúng." };
}

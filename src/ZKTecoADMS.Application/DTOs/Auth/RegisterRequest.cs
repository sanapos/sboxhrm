namespace ZKTecoADMS.Application.DTOs.Auth;

// Đăng ký cửa hàng mới - tạo cả Store và User (owner)
public record RegisterRequest(
    string StoreName,      // Tên cửa hàng
    string Email,          // Email đăng nhập
    string Password,       // Mật khẩu
    string? PhoneNumber,   // Số điện thoại (tùy chọn)
    string? StoreCode      // Mã cửa hàng tùy chỉnh (tùy chọn, auto-generate nếu không có)
);

// Đăng ký nhân viên cho cửa hàng (sau này)
public record RegisterEmployeeRequest(
    string Email, 
    string Password, 
    string FirstName, 
    string LastName, 
    string? PhoneNumber
);
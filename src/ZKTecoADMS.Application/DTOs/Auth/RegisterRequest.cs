namespace ZKTecoADMS.Application.DTOs.Auth;

// Đăng ký cửa hàng mới - tạo cả Store và User (owner)
public record RegisterRequest(
    string StoreName,      // Tên cửa hàng
    string Email,          // Email đăng nhập
    string Password,       // Mật khẩu
    string PhoneNumber,    // Số điện thoại (bắt buộc)
    string Province,       // Tỉnh / thành phố (bắt buộc)
    string? StoreCode = null,     // Mã cửa hàng tùy chỉnh (tùy chọn, auto-generate nếu không có)
    string? AgentCode = null,     // Mã đại lý (tùy chọn). Nếu hợp lệ → cửa hàng sẽ thuộc đại lý này
    string? Agent = null,         // Alias query ?agent=
    string? Ref = null,           // Alias query ?ref=
    Guid? ServicePackageId = null, // Gói dịch vụ dùng thử được chọn khi đăng ký
    string? SellProfile = null     // Ngành hàng POS (Retail, Restaurant, Hotel, …)
);

// Đăng ký nhân viên cho cửa hàng (sau này)
public record RegisterEmployeeRequest(
    string Email, 
    string Password, 
    string FirstName, 
    string LastName, 
    string? PhoneNumber
);
namespace ZKTecoADMS.Application.DTOs.SystemAdmin;

/// <summary>
/// Agent (Đại lý) DTO
/// </summary>
public record AgentDto(
    Guid Id,
    string Name,
    string Code,
    string? Description,
    string? Address,
    string? Phone,
    string? Email,
    bool IsActive,
    string? LicenseKey,
    DateTime? LicenseExpiryDate,
    int MaxStores,
    int CurrentStoresCount,
    Guid? UserId,
    string? UserEmail,
    DateTime CreatedAt,
    // License Key Stats
    int TotalLicenseKeys,
    int UsedLicenseKeys,
    int AvailableLicenseKeys,
    // Store Stats
    int ActiveStoresCount,
    int LockedStoresCount,
    // Registration Info
    string? RegistrationToken,
    DateTime? RegistrationTokenExpiry,
    bool IsRegistrationCompleted,
    string? RegistrationLink
);

/// <summary>
/// Request tạo Agent mới. Nếu cung cấp Email + Password sẽ tạo luôn tài khoản đăng nhập (role Agent),
/// nếu không sẽ chỉ sinh token để đại lý tự đăng ký qua link.
/// </summary>
public record CreateAgentRequest(
    string Name,
    string Code,
    string? Description,
    string? Address,
    string? Phone,
    string? Email, // Email liên hệ / dùng để đăng nhập nếu kèm Password
    int MaxStores = 10,
    int TokenValidDays = 30, // Token có hiệu lực bao nhiêu ngày
    string? Password = null  // Nếu có → tạo ngay tài khoản Agent với mật khẩu này
);

/// <summary>
/// Request cập nhật Agent
/// </summary>
public record UpdateAgentRequest(
    string? Name,
    string? Description,
    string? Address,
    string? Phone,
    string? Email,
    int? MaxStores,
    bool? IsActive,
    string? LicenseKey,
    DateTime? LicenseExpiryDate
);

/// <summary>
/// Request tự đăng ký tài khoản đại lý
/// </summary>
public record AgentSelfRegisterRequest(
    string RegistrationToken,
    string Email,
    string Password,
    string ConfirmPassword,
    string? FullName
);

/// <summary>
/// Response khi lấy thông tin đại lý qua token
/// </summary>
public record AgentRegistrationInfoResponse(
    Guid AgentId,
    string AgentName,
    string AgentCode,
    string? Description,
    string? Address,
    string? Phone,
    string? ContactEmail,
    bool IsTokenValid,
    DateTime? TokenExpiry,
    string? Message
);

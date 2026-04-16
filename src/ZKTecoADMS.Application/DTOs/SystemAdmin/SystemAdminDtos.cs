namespace ZKTecoADMS.Application.DTOs.SystemAdmin;

/// <summary>
/// Thống kê tổng quan hệ thống
/// </summary>
public record SystemDashboardDto(
    int TotalStores,
    int ActiveStores,
    int InactiveStores,
    int TotalUsers,
    int TotalDevices,
    int OnlineDevices,
    int OfflineDevices,
    int TotalAttendanceToday,
    List<StoreStatDto> TopStoresByUsers,
    List<RecentActivityDto> RecentActivities,
    // License stats
    int TotalLicenseKeys,
    int UsedLicenseKeys,
    int AvailableLicenseKeys,
    int TotalAgents,
    // Time-filtered stats
    int StoresCreatedInPeriod,
    int KeysActivatedInPeriod,
    int KeysCreatedInPeriod,
    int UsersCreatedInPeriod,
    int LockedStores,
    // Store attendance breakdown
    List<StoreAttendanceDto> StoreAttendances
);

/// <summary>
/// Thống kê cửa hàng
/// </summary>
public record StoreStatDto(
    Guid Id,
    string Name,
    string Code,
    int UserCount,
    int DeviceCount,
    bool IsActive
);

/// <summary>
/// Chấm công theo cửa hàng
/// </summary>
public record StoreAttendanceDto(
    string StoreName,
    int Count
);

/// <summary>
/// Hoạt động gần đây
/// </summary>
public record RecentActivityDto(
    Guid Id,
    string ActivityType,
    string Description,
    string? StoreName,
    string? UserName,
    DateTime CreatedAt
);

/// <summary>
/// Thông tin cửa hàng cho system admin - Chi tiết đầy đủ
/// </summary>
public record StoreDetailDto(
    Guid Id,
    string Name,
    string Code,
    string? Description,
    string? Address,
    string? Phone,
    bool IsActive,
    bool IsLocked,
    string? LockReason,
    // License & Subscription
    string LicenseType,
    string? LicenseKey,
    DateTime? ExpiryDate,
    int MaxUsers,
    int MaxDevices,
    int RenewalCount,
    // Service Package
    Guid? ServicePackageId,
    string? ServicePackageName,
    DateTime? TrialStartDate,
    int TrialDays,
    // Owner
    Guid? OwnerId,
    string? OwnerName,
    string? OwnerEmail,
    // Agent
    Guid? AgentId,
    string? AgentName,
    string? AgentEmail,
    // Stats
    int UserCount,
    int DeviceCount,
    int EmployeeCount,
    // Timestamps
    DateTime CreatedAt,
    DateTime? UpdatedAt,
    // Activity
    DateTime? LastActivityAt = null
);

/// <summary>
/// Thông tin user cho system admin (xem cross-store)
/// </summary>
public record SystemUserDto(
    Guid Id,
    string Email,
    string FullName,
    string Role,
    Guid? StoreId,
    string? StoreName,
    string? StoreCode,
    bool IsActive,
    DateTime CreatedAt,
    DateTime? LastLoginAt
);

/// <summary>
/// Thông tin thiết bị cho system admin
/// </summary>
public record SystemDeviceDto(
    Guid Id,
    string SerialNumber,
    string Name,
    string? IPAddress,
    bool IsOnline,
    Guid? StoreId,
    string? StoreName,
    string? StoreCode,
    DateTime? LastSyncAt,
    DateTime CreatedAt
);

/// <summary>
/// Activity log
/// </summary>
public record ActivityLogDto(
    Guid Id,
    string Type,
    string Action,
    string Description,
    Guid? UserId,
    string? UserName,
    Guid? StoreId,
    string? StoreName,
    string? IpAddress,
    string? UserAgent,
    DateTime CreatedAt
);

/// <summary>
/// Request tạo store mới
/// </summary>
public record CreateStoreRequest(
    string Name,
    string Code,
    string? Description,
    string? Address,
    string? Phone,
    string? OwnerEmail,
    string? OwnerPassword,
    string? OwnerFullName
);

/// <summary>
/// Request cập nhật store
/// </summary>
public record UpdateStoreRequest(
    string Name,
    string? Description,
    string? Address,
    string? Phone
);

// ═══════════════════════ SERVICE PACKAGE DTOs ═══════════════════════

public record ServicePackageDto(
    Guid Id,
    string Name,
    string? Description,
    bool IsActive,
    int DefaultDurationDays,
    int MaxUsers,
    int MaxDevices,
    List<string> AllowedModules,
    int StoreCount,
    DateTime CreatedAt,
    DateTime? UpdatedAt
);

public record CreateServicePackageRequest(
    string Name,
    string? Description,
    int DefaultDurationDays,
    int MaxUsers,
    int MaxDevices,
    List<string> AllowedModules
);

public record UpdateServicePackageRequest(
    string Name,
    string? Description,
    int DefaultDurationDays,
    int MaxUsers,
    int MaxDevices,
    List<string> AllowedModules,
    bool IsActive
);

/// <summary>
/// Danh sách tất cả module/chức năng có thể chọn cho gói dịch vụ
/// </summary>
public record FeatureModuleDto(
    string Code,
    string DisplayName,
    string? Description,
    string Category
);

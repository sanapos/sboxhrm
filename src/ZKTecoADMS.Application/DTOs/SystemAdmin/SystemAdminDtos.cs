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
    string? Province,
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
    DateTime? LastLoginAt,
    string? PlainTextPassword = null,
    Guid? AgentId = null,
    string? AgentName = null
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
    DateTime CreatedAt,
    Guid? AgentId = null,
    string? AgentName = null,
    bool IsClaimed = false
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
    string? Province,
    string? Phone
);

/// <summary>
/// Vai trò có thể gán cho user thuộc cửa hàng (theo phân quyền cửa hàng).
/// </summary>
public record StoreRoleOptionDto(
    string RoleName,
    string RoleDisplayName
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
    int MaxAccessDevices,
    bool AllowWeb,
    bool AllowMobile,
    int MaxBranches,
    bool AllowFcm,
    List<string> AllowedFcmCategories,
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
    List<string> AllowedModules,
    int MaxAccessDevices = 0,
    bool AllowWeb = true,
    bool AllowMobile = true,
    int MaxBranches = 0,
    bool AllowFcm = true,
    List<string>? AllowedFcmCategories = null
);

public record UpdateServicePackageRequest(
    string Name,
    string? Description,
    int DefaultDurationDays,
    int MaxUsers,
    int MaxDevices,
    List<string> AllowedModules,
    bool IsActive,
    int MaxAccessDevices = 0,
    bool AllowWeb = true,
    bool AllowMobile = true,
    int MaxBranches = 0,
    bool AllowFcm = true,
    List<string>? AllowedFcmCategories = null
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

/// <summary>Tổng quan POS đa cửa hàng cho Super Admin / đại lý.</summary>
public record PosOverviewDto(
    int StoresWithPosModule,
    int StoresWithSalesInPeriod,
    decimal TodayRevenue,
    int TodayOrders,
    int TodayCancelled,
    int TodayQrOrders,
    decimal PeriodRevenue,
    int PeriodOrders,
    decimal PeriodAvgTicket,
    int PeriodQrOrders,
    int OpenDraftOrders,
    int OpenCashierShifts,
    int PrintAgentsTotal,
    int PrintAgentsOnline,
    int PrintersTotal,
    int PrintersUnhealthy,
    int PrintJobsFailed24h,
    int PrintJobsQueued,
    int KitchenJobsFailed24h,
    int KitchenJobsQueued,
    int OutOfStockSkus,
    int BelowMinSkus,
    int EinvoiceFailed,
    List<PosStoreRevenueDto> TopStoresByRevenue,
    List<PosStoreSnapshotDto> Stores
);

public record PosStoreRevenueDto(
    Guid StoreId,
    string StoreName,
    string StoreCode,
    decimal Revenue,
    int Orders
);

public record PosStoreSnapshotDto(
    Guid StoreId,
    string StoreName,
    string StoreCode,
    bool HasPosModule,
    bool IsActive,
    decimal TodayRevenue,
    int TodayOrders,
    decimal PeriodRevenue,
    int PeriodOrders,
    int PrintAgentsOnline,
    int PrintAgentsTotal,
    int PrintersUnhealthy,
    int PrintersTotal,
    int PrintJobsFailed24h,
    int OpenDraftOrders,
    int OutOfStockSkus
);

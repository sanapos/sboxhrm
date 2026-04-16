using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Audit log để theo dõi các hoạt động hệ thống
/// </summary>
public class AuditLog : Entity<Guid>
{
    /// <summary>
    /// Loại hành động (Create, Update, Delete, Login, Logout, etc.)
    /// </summary>
    public string Action { get; set; } = string.Empty;
    
    /// <summary>
    /// Entity/Module bị tác động (Store, User, Device, LicenseKey, etc.)
    /// </summary>
    public string EntityType { get; set; } = string.Empty;
    
    /// <summary>
    /// ID của entity bị tác động
    /// </summary>
    public string? EntityId { get; set; }
    
    /// <summary>
    /// Tên/Mô tả của entity bị tác động
    /// </summary>
    public string? EntityName { get; set; }
    
    /// <summary>
    /// Chi tiết thay đổi (JSON format)
    /// </summary>
    public string? Details { get; set; }
    
    /// <summary>
    /// ID người thực hiện
    /// </summary>
    public Guid? UserId { get; set; }
    
    /// <summary>
    /// Email người thực hiện
    /// </summary>
    public string? UserEmail { get; set; }
    
    /// <summary>
    /// Tên người thực hiện
    /// </summary>
    public string? UserName { get; set; }
    
    /// <summary>
    /// Role của người thực hiện
    /// </summary>
    public string? UserRole { get; set; }
    
    /// <summary>
    /// ID Store liên quan (nếu có)
    /// </summary>
    public Guid? StoreId { get; set; }
    
    /// <summary>
    /// Tên Store liên quan (nếu có)
    /// </summary>
    public string? StoreName { get; set; }
    
    /// <summary>
    /// Địa chỉ IP của người thực hiện
    /// </summary>
    public string? IpAddress { get; set; }
    
    /// <summary>
    /// User Agent của trình duyệt/thiết bị
    /// </summary>
    public string? UserAgent { get; set; }
    
    /// <summary>
    /// Thời gian thực hiện
    /// </summary>
    public DateTime Timestamp { get; set; } = DateTime.UtcNow;
    
    /// <summary>
    /// Trạng thái (Success, Failed, Warning)
    /// </summary>
    public string Status { get; set; } = "Success";
    
    /// <summary>
    /// Thông báo lỗi (nếu có)
    /// </summary>
    public string? ErrorMessage { get; set; }
}

/// <summary>
/// Các loại action phổ biến
/// </summary>
public static class AuditActions
{
    // Authentication
    public const string Login = "Login";
    public const string Logout = "Logout";
    public const string LoginFailed = "LoginFailed";
    
    // CRUD
    public const string Create = "Create";
    public const string Update = "Update";
    public const string Delete = "Delete";
    
    // Store
    public const string StoreLocked = "StoreLocked";
    public const string StoreUnlocked = "StoreUnlocked";
    public const string StoreDataDeleted = "StoreDataDeleted";
    
    // License
    public const string LicenseGenerated = "LicenseGenerated";
    public const string LicenseActivated = "LicenseActivated";
    public const string LicenseRevoked = "LicenseRevoked";
    public const string SubscriptionExtended = "SubscriptionExtended";
    
    // Device
    public const string DeviceClaimed = "DeviceClaimed";
    public const string DeviceReleased = "DeviceReleased";
    public const string DeviceCommandSent = "DeviceCommandSent";
    
    // User
    public const string PasswordChanged = "PasswordChanged";
    public const string CredentialsUpdated = "CredentialsUpdated";
    public const string SuperAdminCreated = "SuperAdminCreated";
    
    // Agent
    public const string AgentCreated = "AgentCreated";
    public const string AgentLicenseAssigned = "AgentLicenseAssigned";
    
    // Settings
    public const string SettingsUpdated = "SettingsUpdated";
}

/// <summary>
/// Các loại entity phổ biến
/// </summary>
public static class AuditEntityTypes
{
    public const string Store = "Store";
    public const string User = "User";
    public const string Device = "Device";
    public const string LicenseKey = "LicenseKey";
    public const string Agent = "Agent";
    public const string Employee = "Employee";
    public const string Attendance = "Attendance";
    public const string Settings = "Settings";
    public const string System = "System";
}

using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// License Key - Mã kích hoạt phần mềm cho cửa hàng
/// </summary>
public class LicenseKey : Entity<Guid>
{
    /// <summary>
    /// Mã key kích hoạt (unique)
    /// </summary>
    public string Key { get; set; } = string.Empty;
    
    /// <summary>
    /// Loại gói (Trial, Basic, Standard, Premium, Enterprise)
    /// </summary>
    public LicenseType LicenseType { get; set; } = LicenseType.Basic;
    
    /// <summary>
    /// Số ngày hiệu lực
    /// </summary>
    public int DurationDays { get; set; } = 30;
    
    /// <summary>
    /// Số lượng user tối đa được phép
    /// </summary>
    public int MaxUsers { get; set; } = 10;
    
    /// <summary>
    /// Số lượng thiết bị tối đa được phép
    /// </summary>
    public int MaxDevices { get; set; } = 2;
    
    /// <summary>
    /// Key đã được sử dụng chưa
    /// </summary>
    public bool IsUsed { get; set; } = false;
    
    /// <summary>
    /// Ngày key được kích hoạt
    /// </summary>
    public DateTime? ActivatedAt { get; set; }
    
    /// <summary>
    /// Store đã sử dụng key này (nullable nếu chưa dùng)
    /// </summary>
    public Guid? StoreId { get; set; }
    public virtual Store? Store { get; set; }
    
    /// <summary>
    /// Agent đã mua/sở hữu key này (null nếu do SuperAdmin tạo trực tiếp)
    /// </summary>
    public Guid? AgentId { get; set; }
    public virtual Agent? Agent { get; set; }
    
    /// <summary>
    /// Gói dịch vụ liên kết (nullable)
    /// </summary>
    public Guid? ServicePackageId { get; set; }
    public virtual ServicePackage? ServicePackage { get; set; }
    
    /// <summary>
    /// Ghi chú
    /// </summary>
    public string? Notes { get; set; }
    
    /// <summary>
    /// Key có active không (có thể bị revoke)
    /// </summary>
    public bool IsActive { get; set; } = true;
}

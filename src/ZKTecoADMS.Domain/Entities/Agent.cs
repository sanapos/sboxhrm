using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Đại lý - quản lý nhiều cửa hàng
/// </summary>
public class Agent : AuditableEntity<Guid>
{
    public string Name { get; set; } = string.Empty;
    public string Code { get; set; } = string.Empty; // Mã đại lý duy nhất
    public string? Description { get; set; }
    public string? Address { get; set; }
    public string? Phone { get; set; }
    public string? Email { get; set; }
    public new bool IsActive { get; set; } = true;
    
    // License/Key management
    public string? LicenseKey { get; set; }
    public DateTime? LicenseExpiryDate { get; set; }
    public int MaxStores { get; set; } = 10; // Số cửa hàng tối đa được quản lý
    
    // Self-registration token
    public string? RegistrationToken { get; set; } // Token để đại lý tự đăng ký tài khoản
    public DateTime? RegistrationTokenExpiry { get; set; } // Hạn sử dụng token
    public bool IsRegistrationCompleted { get; set; } = false; // Đại lý đã hoàn thành đăng ký chưa
    
    // Tài khoản đại lý
    public Guid? UserId { get; set; }
    public virtual ApplicationUser? User { get; set; }
    
    // Danh sách cửa hàng thuộc đại lý
    public virtual ICollection<Store> Stores { get; set; } = [];
    
    // Danh sách License Key thuộc đại lý
    public virtual ICollection<LicenseKey> LicenseKeys { get; set; } = [];
}

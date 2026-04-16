using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Domain.Entities;

public class Store : Entity<Guid>
{
    public string Name { get; set; } = string.Empty;
    public string Code { get; set; } = string.Empty; // Mã cửa hàng duy nhất (ví dụ: sanapos)
    public string? Description { get; set; }
    public string? Address { get; set; }
    public string? Phone { get; set; }
    public bool IsActive { get; set; } = true;

    // Lock status
    public bool IsLocked { get; set; } = false;
    public string? LockReason { get; set; }
    public DateTime? LockedAt { get; set; }

    // License
    public LicenseType LicenseType { get; set; } = LicenseType.Basic;
    public string? LicenseKey { get; set; }
    public DateTime? ExpiryDate { get; set; }
    public int MaxUsers { get; set; } = 10;
    public int MaxDevices { get; set; } = 2;

    /// <summary>
    /// Số lần gia hạn (tối đa 3)
    /// </summary>
    public int RenewalCount { get; set; } = 0;

    // Service Package
    public Guid? ServicePackageId { get; set; }
    public virtual ServicePackage? ServicePackage { get; set; }

    /// <summary>
    /// Ngày bắt đầu dùng thử (mặc định khi tạo store)
    /// </summary>
    public DateTime? TrialStartDate { get; set; }

    /// <summary>
    /// Số ngày dùng thử (mặc định 14)
    /// </summary>
    public int TrialDays { get; set; } = 14;

    // Owner của cửa hàng (nullable để có thể tạo store trước khi gán owner)
    public Guid? OwnerId { get; set; }
    public virtual ApplicationUser? Owner { get; set; }

    // Danh sách nhân viên thuộc cửa hàng
    public virtual ICollection<ApplicationUser> Users { get; set; } = [];

    // Danh sách thiết bị thuộc cửa hàng
    public virtual ICollection<Device> Devices { get; set; } = [];

    // Agent quản lý cửa hàng
    public Guid? AgentId { get; set; }
    public virtual Agent? Agent { get; set; }

    // License keys
    public virtual ICollection<LicenseKey> LicenseKeys { get; set; } = [];
}

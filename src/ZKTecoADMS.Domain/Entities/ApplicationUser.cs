using Microsoft.AspNetCore.Identity;

namespace ZKTecoADMS.Domain.Entities;

public class ApplicationUser : IdentityUser<Guid>
{
    public string? FirstName { get; set; }
    public string? LastName { get; set; }
    public UserRefreshToken? RefreshToken { get; set; } = null!;
    public DateTime CreatedAt { get; set; }
    public string? CreatedBy { get; set; }
    public string? Role { get; set; }
    public bool IsActive { get; set; } = true;
    public DateTime? LastLoginAt { get; set; }
    
    // Manager-Employee Relationship (1-Many)
    public Guid? ManagerId { get; set; }
    public virtual ApplicationUser? Manager { get; set; }

    public virtual Employee? Employee { get; set; }
    
    public virtual ICollection<Device> Devices { get; set; } = [];
    
    // Shift relationships
    public virtual ICollection<Shift> RequestedShifts { get; set; } = [];
    public virtual ICollection<Shift> ApprovedShifts { get; set; } = [];
    
    // Leave relationships
    public virtual ICollection<Leave> RequestedLeaves { get; set; } = [];
    public virtual ICollection<Leave> ApprovedLeaves { get; set; } = [];
    public virtual ICollection<ApplicationUser> ManagedEmployees { get; set; } = [];
    public virtual ICollection<Leave> ManagedLeaves { get; set; } = [];
    
    // Store relationship - User thuộc về một cửa hàng
    public Guid? StoreId { get; set; }
    public virtual Store? Store { get; set; }
    
    // Nếu user là owner của cửa hàng
    public virtual Store? OwnedStore { get; set; }

    public string FullName => $"{LastName} {FirstName}";

    public string GetFullName()
    {
        return FullName;
    }

}

using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Nhân viên được phép chấm công tại một vị trí/chi nhánh (MobileWorkLocation).
/// </summary>
public class MobileLocationEmployee : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    [Required]
    public Guid WorkLocationId { get; set; }
    public virtual MobileWorkLocation? WorkLocation { get; set; }

    /// <summary>ApplicationUserId (cùng OdooEmployeeId trên bản ghi chấm công).</summary>
    [Required]
    [MaxLength(100)]
    public string EmployeeId { get; set; } = string.Empty;

    [MaxLength(200)]
    public string? EmployeeName { get; set; }
}

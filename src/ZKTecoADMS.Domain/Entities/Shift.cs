using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Domain.Entities;

public class Shift : AuditableEntity<Guid>
{
    [Required]
    public Guid EmployeeUserId { get; set; }
    
    [Required]
    public DateTime StartTime { get; set; }
    
    [Required]
    public DateTime EndTime { get; set; }

    [Required]
    public int MaximumAllowedLateMinutes { get; set; } = 30;

    [Required]
    public int MaximumAllowedEarlyLeaveMinutes { get; set; } = 30;

    [Required]
    public int BreakTimeMinutes { get; set; } = 60;
    
    [MaxLength(500)]
    public string? Description { get; set; }
    
    [Required]
    public ShiftStatus Status { get; set; } = ShiftStatus.Pending;
    
    [MaxLength(500)]
    public string? RejectionReason { get; set; }

    public Guid? CheckInAttendanceId { get; set; }

    public Guid? CheckOutAttendanceId { get; set; }

    public virtual Attendance? CheckInAttendance { get; set; }

    public virtual Attendance? CheckOutAttendance { get; set; }
    
    /// <summary>
    /// Cửa hàng mà ca làm việc thuộc về
    /// </summary>
    public Guid? StoreId { get; set; }
    public virtual Store? Store { get; set; }
    
    // Navigation Properties
    public virtual ApplicationUser EmployeeUser { get; set; } = null!;

    public virtual Leave? Leave { get; set; }
}

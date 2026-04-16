using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Xếp lịch làm việc - Work Schedule
/// </summary>
public class WorkSchedule : AuditableEntity<Guid>
{
    [Required]
    public Guid EmployeeUserId { get; set; }

    /// <summary>
    /// Ngày làm việc
    /// </summary>
    [Required]
    public DateTime Date { get; set; }

    /// <summary>
    /// Ca làm việc
    /// </summary>
    public Guid? ShiftId { get; set; }

    /// <summary>
    /// Giờ bắt đầu (override nếu khác shift)
    /// </summary>
    public TimeSpan? StartTime { get; set; }

    /// <summary>
    /// Giờ kết thúc (override nếu khác shift)
    /// </summary>
    public TimeSpan? EndTime { get; set; }

    /// <summary>
    /// Là ngày nghỉ phép?
    /// </summary>
    public bool IsDayOff { get; set; } = false;

    /// <summary>
    /// Ghi chú
    /// </summary>
    [MaxLength(500)]
    public string? Note { get; set; }

    /// <summary>
    /// Người tạo lịch (thường là Manager)
    /// </summary>
    public Guid? AssignedById { get; set; }
    
    /// <summary>
    /// Cửa hàng mà lịch làm việc thuộc về
    /// </summary>
    public Guid? StoreId { get; set; }
    public virtual Store? Store { get; set; }

    // Navigation Properties
    public virtual Employee Employee { get; set; } = null!;
    public virtual ShiftTemplate? Shift { get; set; }
    public virtual ApplicationUser? AssignedBy { get; set; }
}
